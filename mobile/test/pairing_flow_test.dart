import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/core/networking/connection_state.dart';
import 'package:orbit_mobile/core/networking/orbit_websocket_client.dart';
import 'package:orbit_mobile/core/storage/local_storage.dart';
import 'package:orbit_mobile/features/connection/controllers/connection_controller.dart';
import 'package:orbit_mobile/features/pairing/controllers/pairing_controller.dart';
import 'package:orbit_mobile/protocol/models/pairing_models.dart';

class InMemoryStorage implements ILocalStorage {
  String? deviceId;
  PairedDeviceRecord? pairedDevice;
  Map<String, dynamic>? recentConn;

  @override
  Future<String> getOrCreateInstallationDeviceId() async {
    deviceId ??= 'dev_stable_mock_777';
    return deviceId!;
  }

  @override
  Future<void> clearPairedDevice() async {
    pairedDevice = null;
  }

  @override
  Future<PairedDeviceRecord?> getPairedDevice() async => pairedDevice;

  @override
  Future<Map<String, dynamic>?> getRecentConnection() async => recentConn;

  @override
  Future<void> savePairedDevice(PairedDeviceRecord record) async {
    pairedDevice = record;
  }

  @override
  Future<void> saveRecentConnection(String host, int port) async {
    recentConn = {'host': host, 'port': port};
  }

  bool _showHiddenFiles = false;

  @override
  Future<void> saveShowHiddenFiles(bool show) async {
    _showHiddenFiles = show;
  }

  @override
  Future<bool> getShowHiddenFiles() async => _showHiddenFiles;
}

class MockOrbitServer {
  HttpServer? _server;
  final List<WebSocket> _clients = [];
  final Map<WebSocket, bool> _pairedSockets = {};
  final Map<WebSocket, String> _socketDeviceIds = {};
  final Map<String, Map<String, dynamic>> _pairedDevices = {};
  String currentPairingCode = '123456';

  int get port => _server?.port ?? 0;
  int get activeClientCount => _clients.length;
  int get pairedConnectedCount =>
      _socketDeviceIds.values.toSet().where((id) => _pairedDevices.containsKey(id)).length;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.transform(WebSocketTransformer()).listen(_handleSocket);
  }

  void _handleSocket(WebSocket ws) {
    _clients.add(ws);
    _pairedSockets[ws] = false;

    // Send welcome event
    ws.add(jsonEncode({
      'type': 'event',
      'event': 'welcome',
      'payload': {
        'server': 'Orbit Desktop Agent Mock',
        'version': '0.1.0',
        'protocol': '1.0',
      },
    }));

    ws.listen(
      (data) => _handleMessage(ws, data),
      onDone: () {
        _clients.remove(ws);
        _pairedSockets.remove(ws);
        _socketDeviceIds.remove(ws);
      },
      onError: (_) {
        _clients.remove(ws);
        _pairedSockets.remove(ws);
        _socketDeviceIds.remove(ws);
      },
    );
  }

  void _handleMessage(WebSocket ws, dynamic data) {
    final decoded = jsonDecode(data.toString()) as Map<String, dynamic>;
    final id = decoded['id'] as String;
    final action = decoded['action'] as String;
    final payload = (decoded['payload'] as Map<String, dynamic>?) ?? {};

    // Check authorization for protected endpoints
    final isPaired = _pairedSockets[ws] ?? false;
    final requiresPairing = action != 'ping' && action != 'pairing.verify' && action != 'session.resume';

    if (requiresPairing && !isPaired) {
      ws.add(jsonEncode({
        'id': id,
        'type': 'response',
        'action': action,
        'success': false,
        'error': {
          'code': 'UNAUTHORIZED',
          'message': 'Device must be paired to access this resource.',
        },
      }));
      return;
    }

    switch (action) {
      case 'ping':
        ws.add(jsonEncode({
          'id': id,
          'type': 'response',
          'action': 'ping',
          'success': true,
          'payload': {'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000},
        }));
        break;

      case 'pairing.verify':
        final code = payload['code'] as String?;
        if (code == currentPairingCode) {
          final deviceId = (payload['deviceId'] as String?) ?? 'dev_auto_1';
          final name = (payload['name'] as String?) ?? 'Mock Phone';
          final platform = (payload['platform'] as String?) ?? 'android';

          // Supersede existing connection for this deviceId
          for (final entry in _socketDeviceIds.entries.toList()) {
            if (entry.value == deviceId && entry.key != ws) {
              _pairedSockets[entry.key] = false;
              _socketDeviceIds.remove(entry.key);
            }
          }

          _pairedSockets[ws] = true;
          _socketDeviceIds[ws] = deviceId;
          _pairedDevices[deviceId] = {
            'deviceId': deviceId,
            'name': name,
            'platform': platform,
          };

          // Emit device.paired event
          ws.add(jsonEncode({
            'type': 'event',
            'event': 'device.paired',
            'payload': {
              'deviceId': deviceId,
              'name': name,
              'platform': platform,
              'pairedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            },
          }));

          ws.add(jsonEncode({
            'id': id,
            'type': 'response',
            'action': 'pairing.verify',
            'success': true,
            'payload': {
              'paired': true,
              'deviceId': deviceId,
            },
          }));
        } else {
          ws.add(jsonEncode({
            'id': id,
            'type': 'response',
            'action': 'pairing.verify',
            'success': false,
            'error': {
              'code': 'INVALID_PAIRING_CODE',
              'message': 'Invalid pairing code provided.',
            },
          }));
        }
        break;

      case 'session.resume':
        final deviceId = payload['deviceId'] as String?;
        if (deviceId != null && _pairedDevices.containsKey(deviceId)) {
          // Supersede older socket for this device
          for (final entry in _socketDeviceIds.entries.toList()) {
            if (entry.value == deviceId && entry.key != ws) {
              _pairedSockets[entry.key] = false;
              _socketDeviceIds.remove(entry.key);
            }
          }

          _pairedSockets[ws] = true;
          _socketDeviceIds[ws] = deviceId;

          ws.add(jsonEncode({
            'id': id,
            'type': 'response',
            'action': 'session.resume',
            'success': true,
            'payload': {
              'resumed': true,
              'deviceId': deviceId,
              'name': _pairedDevices[deviceId]!['name'],
              'platform': _pairedDevices[deviceId]!['platform'],
            },
          }));
        } else {
          ws.add(jsonEncode({
            'id': id,
            'type': 'response',
            'action': 'session.resume',
            'success': false,
            'error': {
              'code': 'UNAUTHORIZED',
              'message': 'Device not registered as a paired device.',
            },
          }));
        }
        break;

      case 'ai.task.start':
        ws.add(jsonEncode({
          'id': id,
          'type': 'response',
          'action': 'ai.task.start',
          'success': true,
          'payload': {
            'taskId': 'task_mock_99',
            'status': 'running',
          },
        }));
        break;

      case 'system.info':
        ws.add(jsonEncode({
          'id': id,
          'type': 'response',
          'action': 'system.info',
          'success': true,
          'payload': {
            'hostname': 'dev-workstation',
            'os': 'linux',
            'osVersion': '6.8.0',
            'architecture': 'x86_64',
            'network': [],
          },
        }));
        break;

      default:
        ws.add(jsonEncode({
          'id': id,
          'type': 'response',
          'action': action,
          'success': false,
          'error': {'code': 'NOT_FOUND', 'message': 'Unknown action'},
        }));
    }
  }

  Future<void> stop() async {
    for (final ws in _clients.toList()) {
      await ws.close();
    }
    await _server?.close(force: true);
  }
}

void main() {
  late MockOrbitServer server;

  setUp(() async {
    server = MockOrbitServer();
    await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  group('Orbit Pairing & Session Security Suite (Requirements A-J)', () {
    test('A: WebSocket connection without pairing remains connectedUnpaired and unpaired', () async {
      final client = OrbitWebSocketClient();
      try {
        await client.connect('127.0.0.1', server.port);
        await client.sendPing();

        expect(client.currentState.status, OrbitConnectionStatus.connectedUnpaired);
        expect(client.currentState.isConnected, isTrue);
        expect(client.currentState.isUnpaired, isTrue);
        expect(client.currentState.isPaired, isFalse);

        // Server reports 1 client, but 0 paired connected devices
        expect(server.activeClientCount, 1);
        expect(server.pairedConnectedCount, 0);
      } finally {
        client.dispose();
      }
    });

    test('B: Valid pairing.verify authenticates session and updates state to paired', () async {
      final client = OrbitWebSocketClient();
      final storage = InMemoryStorage();
      final pairingCtrl = PairingController(client, storage);

      try {
        await client.connect('127.0.0.1', server.port);
        pairingCtrl.setCode('123456');

        final success = await pairingCtrl.verifyPairing('127.0.0.1', server.port);

        expect(success, isTrue);
        expect(client.currentState.status, OrbitConnectionStatus.paired);
        expect(client.currentState.isPaired, isTrue);
        expect(client.currentState.isUnpaired, isFalse);

        // Server now sees 1 paired connected device
        expect(server.pairedConnectedCount, 1);
      } finally {
        client.dispose();
      }
    });

    test('C: Invalid pairing.verify rejects pairing and surfaces error without fake connected state', () async {
      final client = OrbitWebSocketClient();
      final storage = InMemoryStorage();
      final pairingCtrl = PairingController(client, storage);

      try {
        await client.connect('127.0.0.1', server.port);
        pairingCtrl.setCode('999999'); // Invalid code

        final success = await pairingCtrl.verifyPairing('127.0.0.1', server.port);

        expect(success, isFalse);
        expect(client.currentState.status, OrbitConnectionStatus.connectedUnpaired);
        expect(client.currentState.isPaired, isFalse);
        expect(pairingCtrl.state.errorMessage, contains('Invalid pairing code'));
        expect(server.pairedConnectedCount, 0);
      } finally {
        client.dispose();
      }
    });

    test('D: Successful QR pairing parses QR, connects, verifies, and pairs in one step', () async {
      final client = OrbitWebSocketClient();
      final storage = InMemoryStorage();
      final connCtrl = ConnectionController(client, storage);

      try {
        final futureExpires = DateTime.now().millisecondsSinceEpoch + 600000;
        final qrPayload = OrbitPairingQrPayload.parse(
          'orbit://pair/v1?host=127.0.0.1&port=${server.port}&code=123456&expires=$futureExpires',
        );

        final success = await connCtrl.pairWithQr(qrPayload);

        expect(success, isTrue);
        expect(client.currentState.status, OrbitConnectionStatus.paired);
        expect(client.currentState.isPaired, isTrue);
        expect(connCtrl.state.savedPairedDevice, isNotNull);
        expect(connCtrl.state.savedPairedDevice!.pcPort, server.port);
        expect(server.pairedConnectedCount, 1);
      } finally {
        client.dispose();
      }
    });

    test('E: Paired device persistence saves record to storage with stable installationDeviceId', () async {
      final client = OrbitWebSocketClient();
      final storage = InMemoryStorage();
      final connCtrl = ConnectionController(client, storage);

      try {
        final qrPayload = OrbitPairingQrPayload(
          host: '127.0.0.1',
          port: server.port,
          code: '123456',
        );

        await connCtrl.pairWithQr(qrPayload);

        final saved = await storage.getPairedDevice();
        expect(saved, isNotNull);
        expect(saved!.deviceId, equals('dev_stable_mock_777'));
        expect(saved.pcPort, equals(server.port));
      } finally {
        client.dispose();
      }
    });

    test('F: Reconnect after pairing preserves device identity', () async {
      final client = OrbitWebSocketClient();
      final storage = InMemoryStorage();
      final connCtrl = ConnectionController(client, storage);

      try {
        final qrPayload = OrbitPairingQrPayload(
          host: '127.0.0.1',
          port: server.port,
          code: '123456',
        );
        await connCtrl.pairWithQr(qrPayload);
        expect(client.currentState.isPaired, isTrue);

        // Disconnect transport
        client.disconnect();
        expect(client.currentState.status, OrbitConnectionStatus.disconnected);

        // Reconnect using connect() which performs session.resume
        final reconnected = await connCtrl.connect(customHost: '127.0.0.1', customPort: server.port);
        expect(reconnected, isTrue);
        expect(client.currentState.isPaired, isTrue);
        expect(server.pairedConnectedCount, 1);
      } finally {
        client.dispose();
      }
    });

    test('G: session.resume after app restart restores session or resets if desktop revoked', () async {
      final storage = InMemoryStorage();

      // Simulate prior paired state in local storage
      await storage.savePairedDevice(PairedDeviceRecord(
        deviceId: 'dev_stable_mock_777',
        pcAddress: '127.0.0.1',
        pcPort: server.port,
        pcDisplayName: 'Workstation',
        mobileDisplayName: 'Test Phone',
        pairedAt: 1234567,
      ));

      // 1. Unknown device on server -> resume fails, stale record cleared, stays unpaired
      final client1 = OrbitWebSocketClient();
      final connCtrl1 = ConnectionController(client1, storage);
      try {
        final ok = await connCtrl1.connect(customHost: '127.0.0.1', customPort: server.port);
        expect(ok, isTrue);
        expect(client1.currentState.isPaired, isFalse);
        expect(client1.currentState.status, OrbitConnectionStatus.connectedUnpaired);
        // Stale record should be cleared from storage
        expect(await storage.getPairedDevice(), isNull);
      } finally {
        client1.dispose();
      }

      // 2. Pair device properly
      final client2 = OrbitWebSocketClient();
      final connCtrl2 = ConnectionController(client2, storage);
      try {
        await connCtrl2.pairWithQr(OrbitPairingQrPayload(
          host: '127.0.0.1',
          port: server.port,
          code: '123456',
        ));
        expect(client2.currentState.isPaired, isTrue);
      } finally {
        client2.dispose();
      }

      // 3. New app launch with valid device on server -> resume succeeds
      final client3 = OrbitWebSocketClient();
      final connCtrl3 = ConnectionController(client3, storage);
      try {
        final ok = await connCtrl3.connect(customHost: '127.0.0.1', customPort: server.port);
        expect(ok, isTrue);
        expect(client3.currentState.isPaired, isTrue);
      } finally {
        client3.dispose();
      }
    });

    test('H: Duplicate connection replacement unbinds older connection for same deviceId', () async {
      final storage = InMemoryStorage();
      final clientA = OrbitWebSocketClient();
      final clientB = OrbitWebSocketClient();

      try {
        final connCtrlA = ConnectionController(clientA, storage);
        await connCtrlA.pairWithQr(OrbitPairingQrPayload(
          host: '127.0.0.1',
          port: server.port,
          code: '123456',
        ));
        expect(clientA.currentState.isPaired, isTrue);
        expect(server.pairedConnectedCount, 1);

        // Client B connects with same device ID via session.resume
        final connCtrlB = ConnectionController(clientB, storage);
        await connCtrlB.connect(customHost: '127.0.0.1', customPort: server.port);
        expect(clientB.currentState.isPaired, isTrue);

        // Server still has exactly 1 paired device counted
        expect(server.pairedConnectedCount, 1);

        // Protected request from superseded clientA is now rejected
        final resA = await clientA.sendRequest('system.info');
        expect(resA.success, isFalse);
        expect(resA.error?.code, equals('UNAUTHORIZED'));

        // Protected request from active clientB is accepted
        final resB = await clientB.sendRequest('system.info');
        expect(resB.success, isTrue);
      } finally {
        clientA.dispose();
        clientB.dispose();
      }
    });

    test('I: Protected AI/System access before pairing is strictly rejected with UNAUTHORIZED', () async {
      final client = OrbitWebSocketClient();
      try {
        await client.connect('127.0.0.1', server.port);

        final aiRes = await client.sendRequest('ai.task.start', payload: {
          'prompt': 'Write code',
        });
        expect(aiRes.success, isFalse);
        expect(aiRes.error?.code, equals('UNAUTHORIZED'));
        expect(aiRes.error?.message, contains('Device must be paired'));

        final sysRes = await client.sendRequest('system.info');
        expect(sysRes.success, isFalse);
        expect(sysRes.error?.code, equals('UNAUTHORIZED'));
      } finally {
        client.dispose();
      }
    });

    test('J: Protected AI/System access after pairing is accepted', () async {
      final client = OrbitWebSocketClient();
      final storage = InMemoryStorage();
      final connCtrl = ConnectionController(client, storage);

      try {
        await connCtrl.pairWithQr(OrbitPairingQrPayload(
          host: '127.0.0.1',
          port: server.port,
          code: '123456',
        ));
        expect(client.currentState.isPaired, isTrue);

        final aiRes = await client.sendRequest('ai.task.start', payload: {
          'prompt': 'Write code',
        });
        expect(aiRes.success, isTrue);
        expect(aiRes.payload?['taskId'], equals('task_mock_99'));

        final sysRes = await client.sendRequest('system.info');
        expect(sysRes.success, isTrue);
        expect(sysRes.payload?['hostname'], equals('dev-workstation'));
      } finally {
        client.dispose();
      }
    });
  });
}
