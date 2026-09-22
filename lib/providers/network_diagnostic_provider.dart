import 'dart:async';

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
    Duration interval = const Duration(minutes: 1),
    Clock? clock,
  })  : _client = client ?? http.Client(),
        _interval = interval,
        _clock = clock ?? DateTime.now;

  static final _pingUri = Uri.parse('https://www.cloudflare.com/cdn-cgi/trace');
  static final _downloadUri =
      Uri.parse('https://speed.cloudflare.com/__down?bytes=2000000');
  static final _uploadUri = Uri.parse('https://speed.cloudflare.com/__up');

  final http.Client _client;
  final Duration _interval;
  final Clock _clock;
  Timer? _timer;
  bool _isRunning = false;
  bool _isTesting = false;
  String? _errorMessage;
  NetworkDiagnosticResult? _result;
  DiagnosticNetworkType _networkType = DiagnosticNetworkType.wifi;

  bool get isRunning => _isRunning;
  bool get isTesting => _isTesting;
  String? get errorMessage => _errorMessage;
  NetworkDiagnosticResult? get result => _result;
  DiagnosticHealth get health => _result?.health ?? DiagnosticHealth.unknown;
  DiagnosticNetworkType get networkType => _networkType;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _timer = Timer.periodic(_interval, (_) => runDiagnostic());
    unawaited(runDiagnostic());
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    notifyListeners();
  }

  Future<void> runDiagnostic() async {
    if (_isTesting) return;
    if (_networkType == DiagnosticNetworkType.offline) {
      _errorMessage = 'Offline mode: no network connection is available.';
      _result = NetworkDiagnosticResult(
        idlePingMs: 1000,
        downloadMbps: 0,
        downloadPingMs: 1000,
        uploadMbps: 0,
        uploadPingMs: 1000,
        packetLossPercent: 100,
        health: DiagnosticHealth.degraded,
        completedAt: _clock(),
      );
      notifyListeners();
      return;
    }
    _isTesting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final idlePingMs = await _measurePing();
      final download = await Future.wait([
        _measureDownload(),
        _measurePingSamples(),
      ]);
      final upload = await Future.wait([
        _measureUpload(),
        _measurePingSamples(),
      ]);

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
    } on Object catch (error) {
      _errorMessage = 'Diagnostic unavailable: $error';
    } finally {
      _isTesting = false;
      notifyListeners();
    }
  }

  void setNetworkType(DiagnosticNetworkType networkType) {
    if (_networkType == networkType) return;
    _networkType = networkType;
    _errorMessage = null;
    notifyListeners();
    unawaited(runDiagnostic());
  }

  Future<double> _measurePing() async {
    final stopwatch = Stopwatch()..start();
    final response = await _client.get(_pingUri);
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

  Future<double> _measureDownload() async {
    final stopwatch = Stopwatch()..start();
    final response = await _client.get(_downloadUri);
    stopwatch.stop();
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw StateError('Download returned HTTP ${response.statusCode}');
    }
    return _megabits(response.bodyBytes.length, stopwatch.elapsed);
  }

  Future<double> _measureUpload() async {
    final payload = Uint8List(500000);
    final stopwatch = Stopwatch()..start();
    final response = await _client.post(_uploadUri, body: payload);
    stopwatch.stop();
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw StateError('Upload returned HTTP ${response.statusCode}');
    }
    return _megabits(payload.length, stopwatch.elapsed);
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
    _timer?.cancel();
    _client.close();
    super.dispose();
  }
}