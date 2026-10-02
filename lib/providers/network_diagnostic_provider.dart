import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum DiagnosticNetworkType { wifi, mobileData, offline }
enum DiagnosticHealth { excellent, fair, poor, degraded, unknown }

class NetworkDiagnosticResult {
  const NetworkDiagnosticResult({
    required this.idlePingMs,
    required this.packetLossPercent,
    required this.downloadMbps,
    required this.downloadPingMs,
    required this.uploadMbps,
    required this.uploadPingMs,
    required this.health,
    required this.completedAt,
  });

  final double idlePingMs;
  final double packetLossPercent;
  final double downloadMbps;
  final double downloadPingMs;
  final double uploadMbps;
  final double uploadPingMs;
  final DiagnosticHealth health;
  final DateTime completedAt;
}

typedef Clock = DateTime Function();

class _PingSummary {
  const _PingSummary(this.averageMs, this.packetLossPercent);

  final double averageMs;
  final double packetLossPercent;
}

class NetworkDiagnosticProvider extends ChangeNotifier {
  NetworkDiagnosticProvider({
    http.Client? client,
    Connectivity? connectivity,
    Stream<List<ConnectivityResult>>? connectivityStream,
    Future<List<ConnectivityResult>> Function()? currentConnectivity,
    Duration interval = const Duration(minutes: 1),
    this.handoverGracePeriod = const Duration(milliseconds: 600),
    this.requestTimeout = const Duration(seconds: 10),
    Clock? clock,
  })  : _client = client ?? http.Client(),
        _connectivity = connectivity ?? Connectivity(),
        _connectivityStream = connectivityStream,
        _currentConnectivity = currentConnectivity,
        _interval = interval,
        _clock = clock ?? DateTime.now {
    _connectivitySubscription =
        (_connectivityStream ?? _connectivity.onConnectivityChanged)
            .listen(_onConnectivityChanged);
    unawaited(_readCurrentConnectivity());
  }

  static final _pingUri = Uri.parse('https://www.cloudflare.com/cdn-cgi/trace');
  static final _uploadUri = Uri.parse('https://speed.cloudflare.com/__up');

  final http.Client _client;
  final Connectivity _connectivity;
  final Stream<List<ConnectivityResult>>? _connectivityStream;
  final Future<List<ConnectivityResult>> Function()? _currentConnectivity;
  final Duration _interval;
  final Clock _clock;
  final Duration handoverGracePeriod;
  final Duration requestTimeout;
  Timer? _timer;
  Timer? _offlineTransitionTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isRunning = false;
  bool _isTesting = false;
  bool? _hasInternet;
  String? _errorMessage;
  NetworkDiagnosticResult? _result;
  DiagnosticNetworkType _networkType = DiagnosticNetworkType.offline;
  int _connectivityVersion = 0;
  int _diagnosticVersion = 0;

  bool get isRunning => _isRunning;
  bool get isTesting => _isTesting;
  bool? get hasInternet => _hasInternet;
  String? get errorMessage => _errorMessage;
  NetworkDiagnosticResult? get result => _result;
  DiagnosticHealth get health => _result?.health ?? DiagnosticHealth.unknown;
  DiagnosticNetworkType get networkType => _networkType;

  Future<void> _readCurrentConnectivity() async {
    final version = _connectivityVersion;
    try {
      final results = await (_currentConnectivity?.call() ??
          _connectivity.checkConnectivity());
      if (version != _connectivityVersion) return;
      _onConnectivityChanged(results);
    } on Object {
      if (version != _connectivityVersion) return;
      _onConnectivityChanged(const [ConnectivityResult.none]);
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    _connectivityVersion++;
    final nextNetworkType = _mapNetworkType(results);
    if (nextNetworkType == DiagnosticNetworkType.offline &&
        _networkType != DiagnosticNetworkType.offline &&
        handoverGracePeriod > Duration.zero) {
      _offlineTransitionTimer?.cancel();
      _offlineTransitionTimer = Timer(handoverGracePeriod, () {
        _offlineTransitionTimer = null;
        _applyNetworkType(DiagnosticNetworkType.offline);
      });
      return;
    }

    _offlineTransitionTimer?.cancel();
    _offlineTransitionTimer = null;
    _applyNetworkType(nextNetworkType);
  }

  DiagnosticNetworkType _mapNetworkType(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      return DiagnosticNetworkType.wifi;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return DiagnosticNetworkType.mobileData;
    }
    return DiagnosticNetworkType.offline;
  }

  void _applyNetworkType(DiagnosticNetworkType networkType) {
    if (_networkType == networkType) return;
    _networkType = networkType;
    _diagnosticVersion++;
    _isTesting = false;
    _hasInternet = null;
    _result = null;
    _errorMessage = null;
    notifyListeners();
    if (_isRunning && networkType != DiagnosticNetworkType.offline) {
      unawaited(runDiagnostic());
    }
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _timer = Timer.periodic(_interval, (_) {
      if (_networkType != DiagnosticNetworkType.offline) {
        unawaited(runDiagnostic());
      }
    });
    if (_networkType != DiagnosticNetworkType.offline) {
      unawaited(runDiagnostic());
    }
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _diagnosticVersion++;
    _isTesting = false;
    notifyListeners();
  }

  Future<void> runDiagnostic() async {
    if (_networkType == DiagnosticNetworkType.offline) {
      return;
    }
    if (_isTesting) return;
    final runVersion = ++_diagnosticVersion;
    final measuredNetworkType = _networkType;
    var internetReachable = false;
    _isTesting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final idlePingMs = await _measurePing();
      _ensureRunIsCurrent(runVersion);
      internetReachable = true;
      _hasInternet = true;
      notifyListeners();
      final download = await Future.wait([
        _measureDownload(measuredNetworkType),
        _measurePingSamples(),
      ]);
      _ensureRunIsCurrent(runVersion);
      final upload = await Future.wait([
        _measureUpload(measuredNetworkType),
        _measurePingSamples(),
      ]);
      _ensureRunIsCurrent(runVersion);

      final downloadMbps = download[0] as double;
      final downloadPings = download[1] as _PingSummary;
      final uploadMbps = upload[0] as double;
      final uploadPings = upload[1] as _PingSummary;
      _result = NetworkDiagnosticResult(
        idlePingMs: idlePingMs,
        downloadMbps: downloadMbps,
        downloadPingMs: downloadPings.averageMs,
        uploadMbps: uploadMbps,
        uploadPingMs: uploadPings.averageMs,
        packetLossPercent: downloadPings.packetLossPercent >
                uploadPings.packetLossPercent
            ? downloadPings.packetLossPercent
            : uploadPings.packetLossPercent,
        health: _classify(
          downloadMbps,
          uploadMbps,
          idlePingMs,
          downloadPings.averageMs,
          uploadPings.averageMs,
          downloadPings.packetLossPercent > uploadPings.packetLossPercent
              ? downloadPings.packetLossPercent
              : uploadPings.packetLossPercent,
        ),
        completedAt: _clock(),
      );
    } on _DiagnosticInterrupted {
      return;
    } on Object {
      if (runVersion == _diagnosticVersion) {
        if (internetReachable) {
          _errorMessage =
              'Internet is available, but live measurements could not finish. Please retry.';
        } else {
          _hasInternet = false;
          _result = null;
          _errorMessage = measuredNetworkType == DiagnosticNetworkType.mobileData
              ? 'Cellular is connected, but there is no internet connection.'
              : 'Wi-Fi is connected, but there is no internet connection.';
        }
      }
    } finally {
      if (runVersion == _diagnosticVersion) {
        _isTesting = false;
        notifyListeners();
      }
    }
  }

  void _ensureRunIsCurrent(int runVersion) {
    if (runVersion != _diagnosticVersion ||
        _networkType == DiagnosticNetworkType.offline) {
      throw const _DiagnosticInterrupted();
    }
  }

  Future<double> _measurePing() async {
    final stopwatch = Stopwatch()..start();
    final response = await _get(_pingUri);
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw StateError('Ping returned HTTP ${response.statusCode}');
    }
    stopwatch.stop();
    return stopwatch.elapsedMicroseconds / 1000;
  }

  Future<_PingSummary> _measurePingSamples() async {
    final samples = <double>[];
    var lostSamples = 0;
    for (var sample = 0; sample < 3; sample++) {
      try {
        samples.add(await _measurePing());
      } on Object {
        lostSamples++;
      }
    }
    final average = samples.isEmpty
        ? 1000.0
        : samples.reduce((total, value) => total + value) / samples.length;
    return _PingSummary(average, lostSamples / 3 * 100);
  }

  Future<double> _measureDownload(DiagnosticNetworkType networkType) async {
    final bytes = networkType == DiagnosticNetworkType.mobileData
        ? 500000
        : 2000000;
    final uri = Uri.https(
      'speed.cloudflare.com',
      '/__down',
      {'bytes': '$bytes'},
    );
    final stopwatch = Stopwatch()..start();
    final response = await _get(uri);
    stopwatch.stop();
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw StateError('Download returned HTTP ${response.statusCode}');
    }
    return _megabits(response.bodyBytes.length, stopwatch.elapsed);
  }

  Future<double> _measureUpload(DiagnosticNetworkType networkType) async {
    final payload = Uint8List(
      networkType == DiagnosticNetworkType.mobileData ? 100000 : 500000,
    );
    final stopwatch = Stopwatch()..start();
    final response = await _post(_uploadUri, payload);
    stopwatch.stop();
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw StateError('Upload returned HTTP ${response.statusCode}');
    }
    return _megabits(payload.length, stopwatch.elapsed);
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri).timeout(requestTimeout);
    } on TimeoutException {
      throw TimeoutException('Network request did not respond in time');
    }
  }

  Future<http.Response> _post(Uri uri, Uint8List body) async {
    try {
      return await _client.post(uri, body: body).timeout(requestTimeout);
    } on TimeoutException {
      throw TimeoutException('Network request did not respond in time');
    }
  }

  double _megabits(int bytes, Duration elapsed) {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) return 0;
    return bytes * 8 / seconds / 1000000;
  }

  DiagnosticHealth _classify(
    double downloadMbps,
    double uploadMbps,
    double idlePingMs,
    double downloadPingMs,
    double uploadPingMs,
    double packetLossPercent,
  ) {
    final highestPing = [idlePingMs, downloadPingMs, uploadPingMs].reduce(
      (highest, value) => value > highest ? value : highest,
    );
    if (packetLossPercent >= 20 || highestPing > 500) {
      return DiagnosticHealth.degraded;
    }
    if (downloadMbps > 10 && uploadMbps > 10) return DiagnosticHealth.excellent;
    if (downloadMbps >= 2 && uploadMbps >= 2) return DiagnosticHealth.fair;
    return DiagnosticHealth.poor;
  }

  @override
  void dispose() {
    _connectivityVersion++;
    _diagnosticVersion++;
    _offlineTransitionTimer?.cancel();
    _timer?.cancel();
    _connectivitySubscription?.cancel();
    _client.close();
    super.dispose();
  }
}

class _DiagnosticInterrupted implements Exception {
  const _DiagnosticInterrupted();
}