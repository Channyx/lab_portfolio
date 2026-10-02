import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_nearby_connections_plus/flutter_nearby_connections_plus.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';

class LocalMeshChatScreen extends StatefulWidget {
  static const routeName = '/activity-4';

  const LocalMeshChatScreen({super.key});

  @override
  State<LocalMeshChatScreen> createState() => _LocalMeshChatScreenState();
}

enum _ConnectivityMode {
  bluetooth,
  wifi,
}

class _LocalMeshChatScreenState extends State<LocalMeshChatScreen> {
  final NearbyService _nearbyService = NearbyService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  List<Device> _devices = [];
  String? _activeDeviceId;
  String? _error;
  bool _isStarting = true;
  bool _isReady = false;
  bool _isRefreshing = false;
  bool _isTogglingRadio = false;
  _ConnectivityMode _connectivityMode = _ConnectivityMode.bluetooth;
  StreamSubscription<dynamic>? _stateSubscription;
  StreamSubscription<dynamic>? _messageSubscription;

  List<Device> get _connectedDevices => _devices
      .where((device) => device.state == SessionState.connected)
      .toList();

  Device? get _activeDevice {
    for (final device in _connectedDevices) {
      if (device.deviceId == _activeDeviceId) return device;
    }
    return _connectedDevices.isEmpty ? null : _connectedDevices.first;
  }

  @override
  void initState() {
    super.initState();
    _stateSubscription = _nearbyService.stateChangedSubscription(
      callback: _onDevicesChanged,
    );
    _messageSubscription = _nearbyService.dataReceivedSubscription(
      callback: _onMessageReceived,
    );
    unawaited(_initializeNearby());
  }

  Future<void> _initializeNearby() async {
    try {
      final suffix = Random.secure().nextInt(1 << 16).toRadixString(16);
      final strategy = _connectivityMode == _ConnectivityMode.wifi
          ? Strategy.Wi_Fi_P2P
          : Strategy.P2P_CLUSTER;

      await _nearbyService.init(
        serviceType: 'meshchat',
        deviceName: 'Mesh-$suffix',
        strategy: strategy,
        callback: (isRunning) async {
          if (!mounted) return;
          if (!isRunning) {
            setState(() {
              _isStarting = false;
              _isReady = false;
              _isRefreshing = false;
              _error = 'Nearby permissions were not granted.';
            });
            return;
          }
          try {
            await _nearbyService.startAdvertisingPeer();
            await _nearbyService.startBrowsingForPeers();
            if (!mounted) return;
            setState(() {
              _isStarting = false;
              _isReady = true;
              _isRefreshing = false;
              _error = null;
            });
          } catch (error) {
            if (!mounted) return;
            setState(() {
              _isStarting = false;
              _isReady = false;
              _isRefreshing = false;
              _error = 'Could not start nearby discovery: $error';
            });
          }
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _isReady = false;
        _isRefreshing = false;
        _error = 'Could not initialize nearby connections: $error';
      });
    }
  }

  void _onDevicesChanged(List<Device> devices) {
    if (!mounted) return;
    setState(() {
      _devices = List<Device>.of(devices);
      if (_activeDeviceId != null &&
          !_devices.any((device) =>
              device.deviceId == _activeDeviceId &&
              device.state == SessionState.connected)) {
        _activeDeviceId = null;
      }
    });
  }

  void _onMessageReceived(dynamic data) {
    final payload = _readPayload(data);
    if (payload == null || !mounted) return;
    setState(() {
      _messages.add(
        _ChatMessage(
          deviceId: payload.$1,
          text: payload.$2,
          isMine: false,
          sentAt: DateTime.now(),
        ),
      );
      _activeDeviceId ??= payload.$1;
    });
    _scrollToLatest();
  }

  (String, String)? _readPayload(dynamic data) {
    dynamic decoded = data;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } on FormatException {
        return null;
      }
    }
    if (decoded is! Map) return null;
    final deviceId =
      (decoded['senderDeviceId'] ?? decoded['deviceId'])?.toString();
    final message = decoded['message']?.toString();
    if (deviceId == null || message == null || message.isEmpty) return null;
    return (deviceId, message);
  }

  Future<void> _connectTo(Device device) async {
    if (device.state == SessionState.connected) {
      setState(() => _activeDeviceId = device.deviceId);
      return;
    }
    if (device.state == SessionState.connecting) return;
    try {
      await _nearbyService.invitePeer(
        deviceID: device.deviceId,
        deviceName: device.deviceName,
      );
    } catch (error) {
      _showMessage('Connection request failed: $error');
    }
  }

  Future<void> _disconnectFrom(Device device) async {
    try {
      await _nearbyService.disconnectPeer(deviceID: device.deviceId);
    } catch (error) {
      _showMessage('Could not disconnect: $error');
    }
  }

  Future<void> _sendMessage() async {
    final device = _activeDevice;
    final text = _messageController.text.trim();
    if (device == null || text.isEmpty) return;
    try {
      await _nearbyService.sendMessage(device.deviceId, text);
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            deviceId: device.deviceId,
            text: text,
            isMine: true,
            sentAt: DateTime.now(),
          ),
        );
        _messageController.clear();
      });
      _scrollToLatest();
    } catch (error) {
      _showMessage('Message could not be sent: $error');
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _stopNearby() async {
    try {
      await _nearbyService.stopNearbyService();
    } catch (_) {}
  }

  Future<void> _refreshDiscovery() async {
    await _restartDiscovery();
  }

  Future<void> _restartDiscovery({_ConnectivityMode? mode}) async {
    if (_isRefreshing) return;
    setState(() {
      if (mode != null) _connectivityMode = mode;
      _isStarting = true;
      _isReady = false;
      _isRefreshing = true;
      _error = null;
      _devices = const [];
      _activeDeviceId = null;
    });
    try {
      await _stopNearby();
    } catch (_) {}
    if (mounted) await _initializeNearby();
  }

  Future<void> _onConnectivityChanged(_ConnectivityMode mode) async {
    try {
      if (_isTogglingRadio || _isRefreshing) return;
      setState(() => _isTogglingRadio = true);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final enabled = mode == _ConnectivityMode.bluetooth
            ? await _nearbyService.requestBluetoothEnabled()
            : await _nearbyService.requestWifiEnabled();
        if (!enabled) {
          if (mounted) setState(() => _isTogglingRadio = false);
          _showMessage(
            mode == _ConnectivityMode.bluetooth
                ? 'Bluetooth was not enabled.'
                : 'Wi-Fi was not enabled.',
          );
          return;
        }
      } else {
        _showMessage(
          'iOS manages Bluetooth and Wi-Fi. Enable radios in Control Center or Settings.',
        );
      }
      if (!mounted) return;
      setState(() => _isTogglingRadio = false);
      await _restartDiscovery(mode: mode);
    } catch (error) {
      if (mounted) setState(() => _isTogglingRadio = false);
      _showMessage('Could not enable the selected radio: $error');
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _messageSubscription?.cancel();
    unawaited(_stopNearby());
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final activeDevice = _activeDevice;
    final activeMessages = _messages
        .where((message) => message.deviceId == activeDevice?.deviceId)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Mesh Chat'),
        actions: [
          IconButton(
            tooltip: appState.isActivityCompleted(4)
                ? 'Mark Activity 4 incomplete'
                : 'Mark Activity 4 complete',
            onPressed: () =>
                context.read<AppStateProvider>().toggleActivityCompletion(4),
            icon: Icon(
              appState.isActivityCompleted(4)
                  ? Icons.check_circle
                  : Icons.check_circle_outline,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildDiscoveryStatus(),
            if (_error != null) _buildErrorBanner(),
            _buildPeerList(),
            const Divider(height: 1),
            Expanded(
              child: activeDevice == null
                  ? _buildEmptyChat()
                  : _buildConversation(activeDevice, activeMessages),
            ),
            _buildComposer(activeDevice),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryStatus() {
    final theme = Theme.of(context);
    final selectedModeLabel = _connectivityMode == _ConnectivityMode.bluetooth
        ? 'Bluetooth discovery'
        : 'Wi‑Fi discovery';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              if (_isStarting)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  _isReady ? Icons.radar : Icons.radar_outlined,
                  size: 18,
                  color: _isReady ? Colors.teal : theme.colorScheme.error,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isStarting
                      ? 'Starting nearby discovery'
                      : _isReady
                          ? 'Discovering nearby devices'
                          : 'Nearby discovery unavailable',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              IconButton(
                tooltip: 'Refresh nearby devices',
                onPressed: _isRefreshing ? null : _refreshDiscovery,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Transport', style: theme.textTheme.labelLarge),
              const SizedBox(width: 10),
              ChoiceChip(
                label: const Text('Bluetooth'),
                selected: _connectivityMode == _ConnectivityMode.bluetooth,
                onSelected: _isTogglingRadio || _isRefreshing
                  ? null
                  : (_) => _onConnectivityChanged(_ConnectivityMode.bluetooth),
                selectedColor: theme.colorScheme.primaryContainer,
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Wi‑Fi'),
                selected: _connectivityMode == _ConnectivityMode.wifi,
                onSelected: _isTogglingRadio || _isRefreshing
                  ? null
                  : (_) => _onConnectivityChanged(_ConnectivityMode.wifi),
                selectedColor: theme.colorScheme.primaryContainer,
              ),
              const Spacer(),
              Text('${_devices.length} found', style: theme.textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeInOutCubic,
            switchOutCurve: Curves.easeInOutCubic,
            child: Container(
              key: ValueKey<String>(selectedModeLabel),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _connectivityMode == _ConnectivityMode.bluetooth
                        ? Icons.bluetooth_connected
                        : Icons.wifi_tethering,
                    size: 16,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$selectedModeLabel · Nearby manages radio selection${_isStarting ? ' · restarting' : ''}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.warning_amber,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 10),
            Expanded(child: Text(_error!)),
          ],
        ),
      ),
    );
  }

  Widget _buildPeerList() {
    if (_devices.isEmpty) {
      return const SizedBox(
        height: 68,
        child: Center(child: Text('No nearby devices yet')),
      );
    }
    return SizedBox(
      height: 92,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _devices.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final device = _devices[index];
          final connected = device.state == SessionState.connected;
          final connecting = device.state == SessionState.connecting;
          final selected = connected && device.deviceId == _activeDevice?.deviceId;
          return ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
            child: Material(
              color: selected
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => connected ? _connectTo(device) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(connected ? Icons.link : Icons.devices_other,
                          color: connected ? Colors.teal : null),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.deviceName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              connected
                                  ? 'Connected'
                                  : connecting
                                      ? 'Pairing…'
                                      : 'Nearby',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      if (!connected)
                        IconButton(
                          tooltip: connecting ? 'Pairing' : 'Connect',
                          onPressed: connecting ? null : () => _connectTo(device),
                          icon: connecting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.add_link),
                        )
                      else
                        IconButton(
                          tooltip: 'Disconnect',
                          onPressed: () => _disconnectFrom(device),
                          icon: const Icon(Icons.link_off),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 42, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              _connectedDevices.isEmpty
                  ? 'Connect to a nearby device to start chatting'
                  : 'Choose a connected device to open its chat',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversation(Device device, List<_ChatMessage> messages) {
    return Column(
      children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.lock_outline),
          title: Text(device.deviceName),
          subtitle: const Text('Direct nearby connection'),
        ),
        const Divider(height: 1),
        Expanded(
          child: messages.isEmpty
              ? const Center(child: Text('No messages in this conversation'))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final colorScheme = Theme.of(context).colorScheme;
                    return Align(
                      alignment: message.isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: message.isMine
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(message.text),
                            const SizedBox(height: 4),
                            Text(
                              TimeOfDay.fromDateTime(message.sentAt)
                                  .format(context),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildComposer(Device? device) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                enabled: device != null,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  hintText: device == null ? 'Connect to chat' : 'Message',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send message',
              onPressed: device == null ? null : _sendMessage,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.deviceId,
    required this.text,
    required this.isMine,
    required this.sentAt,
  });

  final String deviceId;
  final String text;
  final bool isMine;
  final DateTime sentAt;
}