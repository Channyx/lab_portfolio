import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum NetworkInterfaceType { wifi, cellular, offline }

class QueuedNetworkRequest {
  final int id;
  final int totalChunks;
  int completedChunks;
  String status;

  QueuedNetworkRequest({
    required this.id,
    this.totalChunks = 8,
  })  : completedChunks = 0,
        status = 'Queued';

  double get progress => completedChunks / totalChunks;
}

class NetworkMonitorProvider extends ChangeNotifier {
  NetworkMonitorProvider({
    Connectivity? connectivity,
    Stream<List<ConnectivityResult>>? connectivityStream,
    Future<List<ConnectivityResult>> Function()? currentConnectivity,
  })  : _connectivity = connectivity ?? Connectivity(),
        _connectivityStream = connectivityStream,
        _currentConnectivity = currentConnectivity {
    _subscription = (_connectivityStream ?? _connectivity.onConnectivityChanged)
        .listen(_updateNetwork);
    unawaited(_readCurrentNetwork());
  }

  final Connectivity _connectivity;
  final Stream<List<ConnectivityResult>>? _connectivityStream;
  final Future<List<ConnectivityResult>> Function()? _currentConnectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final List<QueuedNetworkRequest> _queuedRequests = [];
  Timer? _requestTimer;
  NetworkInterfaceType _activeInterface = NetworkInterfaceType.offline;
  int _networkUpdateVersion = 0;
  int _nextRequestId = 1;
  int _completedRequestCount = 0;

  NetworkInterfaceType get activeInterface => _activeInterface;
  List<QueuedNetworkRequest> get queuedRequests =>
      List.unmodifiable(_queuedRequests);
  int get completedRequestCount => _completedRequestCount;
  bool get isRequestRunning => _requestTimer != null;

  Future<void> _readCurrentNetwork() async {
    final requestVersion = _networkUpdateVersion;
    try {
      final results =
          await (_currentConnectivity?.call() ?? _connectivity.checkConnectivity());
      if (requestVersion != _networkUpdateVersion) return;
      _updateNetwork(results);
    } on Object {
      if (requestVersion != _networkUpdateVersion) return;
      _updateNetwork(const [ConnectivityResult.none]);
    }
  }

  void _updateNetwork(List<ConnectivityResult> results) {
    _networkUpdateVersion++;
    final nextInterface = _mapInterface(results);
    if (nextInterface == _activeInterface) return;

    _activeInterface = nextInterface;
    if (_activeInterface == NetworkInterfaceType.offline &&
        _requestTimer != null &&
        _queuedRequests.isNotEmpty) {
      _requestTimer?.cancel();
      _requestTimer = null;
      _queuedRequests.first.status = 'Waiting for connection';
    }
    notifyListeners();
    _processQueue();
  }

  NetworkInterfaceType _mapInterface(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      return NetworkInterfaceType.wifi;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return NetworkInterfaceType.cellular;
    }
    return NetworkInterfaceType.offline;
  }

  void enqueueRequest() {
    _queuedRequests.add(
      QueuedNetworkRequest(id: _nextRequestId++),
    );
    notifyListeners();
    _processQueue();
  }

  void simulateNetwork(NetworkInterfaceType interfaceType) {
    _updateNetwork(
      switch (interfaceType) {
        NetworkInterfaceType.wifi => const [ConnectivityResult.wifi],
        NetworkInterfaceType.cellular => const [ConnectivityResult.mobile],
        NetworkInterfaceType.offline => const [ConnectivityResult.none],
      },
    );
  }

  void _processQueue() {
    if (_requestTimer != null ||
        _queuedRequests.isEmpty ||
        _activeInterface == NetworkInterfaceType.offline) {
      return;
    }

    final request = _queuedRequests.first;
    request.status = 'Downloading';
    _requestTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      try {
        _downloadNextChunk(request);
      } on Object {
        // A handover can invalidate an in-flight request. Keep it in the
        // queue and let the connectivity stream restart it when online.
        _requestTimer?.cancel();
        _requestTimer = null;
        request.status = 'Waiting for connection';
        notifyListeners();
        return;
      }

      if (request.completedChunks >= request.totalChunks) {
        request.status = 'Completed';
        _queuedRequests.removeAt(0);
        _completedRequestCount++;
        _requestTimer?.cancel();
        _requestTimer = null;
      }
      notifyListeners();
      _processQueue();
    });
    notifyListeners();
  }

  void _downloadNextChunk(QueuedNetworkRequest request) {
    if (_activeInterface == NetworkInterfaceType.offline) {
      throw StateError('Network handover interrupted the request');
    }
    request.completedChunks++;
  }

  @override
  void dispose() {
    _networkUpdateVersion++;
    _requestTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
