import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../errors/orbit_exception.dart';
import '../../protocol/messages/orbit_request.dart';
import '../../protocol/messages/orbit_response.dart';
import '../../protocol/messages/orbit_event.dart';
import 'connection_state.dart';

class OrbitWebSocketClient {
  static const _uuid = Uuid();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  String? _lastHost;
  int? _lastPort;
  bool _manualDisconnect = false;
  int _reconnectAttempts = 0;

  final Map<String, Completer<OrbitResponse>> _pendingRequests = {};
  final StreamController<OrbitEvent> _eventController =
      StreamController<OrbitEvent>.broadcast();
  final StreamController<OrbitConnectionState> _stateController =
      StreamController<OrbitConnectionState>.broadcast();

  OrbitConnectionState _currentState = const OrbitConnectionState();

  OrbitConnectionState get currentState => _currentState;
  Stream<OrbitConnectionState> get stateStream => _stateController.stream;
  Stream<OrbitEvent> get events => _eventController.stream;

  void _updateState(OrbitConnectionState newState) {
    _currentState = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  Future<void> connect(String host, int port) async {
    _manualDisconnect = false;
    _lastHost = host;
    _lastPort = port;
    _reconnectTimer?.cancel();

    _updateState(_currentState.copyWith(
      status: OrbitConnectionStatus.connecting,
      host: host,
      port: port,
      errorMessage: null,
    ));

    try {
      final uri = Uri.parse('ws://$host:$port');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready.timeout(const Duration(seconds: 5));

      _reconnectAttempts = 0;
      _updateState(_currentState.copyWith(
        status: OrbitConnectionStatus.connectedUnpaired,
      ));

      _subscription = _channel!.stream.listen(
        _handleIncomingMessage,
        onError: _handleError,
        onDone: _handleDone,
        cancelOnError: true,
      );

      _startPingLoop();
    } catch (e) {
      _updateState(_currentState.copyWith(
        status: OrbitConnectionStatus.error,
        errorMessage: 'Connection failed: ${e.toString()}',
      ));
      _scheduleReconnect();
      throw OrbitConnectionException('Failed to connect to ws://$host:$port', cause: e);
    }
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      final raw = message.toString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['type'] as String?;

      if (type == 'response') {
        final response = OrbitResponse.fromJson(decoded);
        final completer = _pendingRequests.remove(response.id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(response);
        }
      } else if (type == 'event') {
        final event = OrbitEvent.fromJson(decoded);
        if (!_eventController.isClosed) {
          _eventController.add(event);
        }
      }
    } catch (e) {
      // Ignore malformed individual frame
    }
  }

  void _handleError(dynamic error) {
    if (_manualDisconnect) return;

    _updateState(_currentState.copyWith(
      status: OrbitConnectionStatus.error,
      errorMessage: error.toString(),
    ));
    _scheduleReconnect();
  }

  void _handleDone() {
    _cleanupChannel();
    if (!_manualDisconnect) {
      _updateState(_currentState.copyWith(
        status: OrbitConnectionStatus.disconnected,
      ));
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _lastHost == null || _lastPort == null) return;
    _reconnectTimer?.cancel();

    _reconnectAttempts++;
    // Exponential backoff: 1s, 2s, 4s, 8s, up to 30s
    final delaySec = min(pow(2, _reconnectAttempts - 1).toInt(), 30);

    _updateState(_currentState.copyWith(
      status: OrbitConnectionStatus.reconnecting,
      errorMessage: 'Reconnecting in $delaySec s (attempt $_reconnectAttempts)...',
    ));

    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (!_manualDisconnect && _lastHost != null && _lastPort != null) {
        connect(_lastHost!, _lastPort!).catchError((_) {});
      }
    });
  }

  Future<OrbitResponse> sendRequest(
    String action, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_channel == null || !_currentState.isConnected) {
      throw const OrbitConnectionException('Not connected to Orbit Desktop');
    }

    final id = 'req_${_uuid.v4().replaceAll('-', '').substring(0, 12)}';
    final request = OrbitRequest(
      id: id,
      action: action,
      payload: payload,
    );

    final completer = Completer<OrbitResponse>();
    _pendingRequests[id] = completer;

    try {
      final jsonString = jsonEncode(request.toJson());
      _channel!.sink.add(jsonString);
    } catch (e) {
      _pendingRequests.remove(id);
      throw OrbitConnectionException('Failed to send request $action', cause: e);
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw OrbitTimeoutException('Request $action timed out after ${timeout.inSeconds}s');
      },
    );
  }

  Future<int> sendPing() async {
    final start = DateTime.now();
    final response = await sendRequest('ping', timeout: const Duration(seconds: 5));
    if (!response.success) {
      throw OrbitProtocolException(
        response.error?.message ?? 'Ping failed',
        code: response.error?.code,
      );
    }
    final rtt = DateTime.now().difference(start).inMilliseconds;
    _updateState(_currentState.copyWith(latencyMs: rtt));
    return rtt;
  }

  void _startPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_currentState.isConnected) {
        sendPing().catchError((_) => 0);
      }
    });
  }

  void markPairing() {
    _updateState(_currentState.copyWith(
      status: OrbitConnectionStatus.pairing,
    ));
  }

  void markPaired(String deviceId) {
    _updateState(_currentState.copyWith(
      status: OrbitConnectionStatus.paired,
      deviceId: deviceId,
    ));
  }

  void markUnpaired() {
    _updateState(_currentState.copyWith(
      status: OrbitConnectionStatus.connectedUnpaired,
      deviceId: null,
    ));
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();

    // Reject all pending requests
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const OrbitConnectionException('Connection closed by user'),
        );
      }
    }
    _pendingRequests.clear();

    _cleanupChannel();
    _updateState(const OrbitConnectionState(
      status: OrbitConnectionStatus.disconnected,
    ));
  }

  void _cleanupChannel() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _stateController.close();
  }
}
