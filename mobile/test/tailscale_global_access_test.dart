import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/core/errors/orbit_exception.dart';
import 'package:orbit_mobile/core/networking/connection_manager.dart';
import 'package:orbit_mobile/core/networking/connection_state.dart';
import 'package:orbit_mobile/core/networking/orbit_websocket_client.dart';
import 'package:orbit_mobile/core/providers.dart';
import 'package:orbit_mobile/core/storage/local_storage.dart';
import 'package:orbit_mobile/features/connection/views/connection_screen.dart';
import 'package:orbit_mobile/features/connection/controllers/connection_controller.dart';
import 'package:orbit_mobile/features/pairing/controllers/pairing_controller.dart';
import 'package:orbit_mobile/features/dashboard/views/dashboard_screen.dart';
import 'package:orbit_mobile/protocol/messages/orbit_event.dart';
import 'package:orbit_mobile/protocol/messages/orbit_response.dart';
import 'package:orbit_mobile/protocol/models/pairing_models.dart';
import 'package:orbit_mobile/protocol/models/system_info.dart';

class MockLocalStorage implements ILocalStorage {
  final Map<String, dynamic> _storage = {};

  @override
  Future<void> savePairedDevice(PairedDeviceRecord record) async {
    _storage['paired_device'] = jsonEncode(record.toJson());
  }

  @override
  Future<PairedDeviceRecord?> getPairedDevice() async {
    final raw = _storage['paired_device'];
    if (raw == null) return null;
    return PairedDeviceRecord.fromJson(jsonDecode(raw as String) as Map<String, dynamic>);
  }

  @override
  Future<void> clearPairedDevice() async {
    _storage.remove('paired_device');
  }

  @override
  Future<void> saveRecentConnection(String host, int port) async {
    _storage['recent'] = {'host': host, 'port': port};
  }

  @override
  Future<Map<String, dynamic>?> getRecentConnection() async {
    return _storage['recent'] as Map<String, dynamic>?;
  }

  @override
  Future<String> getOrCreateInstallationDeviceId() async {
    return 'mock-device-id-12345';
  }

  @override
  Future<void> saveShowHiddenFiles(bool show) async {
    _storage['show_hidden_files'] = show;
  }

  @override
  Future<bool> getShowHiddenFiles() async {
    return _storage['show_hidden_files'] as bool? ?? false;
  }
}

class MockWebSocketClient extends OrbitWebSocketClient {
  bool failNextConnect = false;
  String? lastConnectedHost;
  int? lastConnectedPort;
  OrbitConnectionState _mockState = const OrbitConnectionState();
  final StreamController<OrbitEvent> _mockEvents =
      StreamController<OrbitEvent>.broadcast();

  @override
  OrbitConnectionState get currentState => _mockState;

  @override
  Stream<OrbitEvent> get events => _mockEvents.stream;

  void setMockState(OrbitConnectionState state) {
    _mockState = state;
  }

  Map<String, dynamic> customSystemInfoPayload = {
    'hostname': 'Aburaya',
    'os': 'Linux',
    'osVersion': '6.8.0',
    'architecture': 'x86_64',
    'primaryIp': '192.168.100.4',
    'tailscale': {
      'installed': true,
      'running': true,
      'state': 'connected',
      'ip': '100.83.227.27',
      'device_name': 'aburaya.tail78ef5e.ts.net',
      'tailnet_name': 'moouu70@gmail.com',
    },
  };

  @override
  Future<void> connect(String host, int port) async {
    if (failNextConnect) {
      failNextConnect = false;
      _mockState = _mockState.copyWith(
        status: OrbitConnectionStatus.error,
        errorMessage: 'Failed to connect',
      );
      throw const OrbitConnectionException('Failed to connect');
    }
    lastConnectedHost = host;
    lastConnectedPort = port;
    _mockState = _mockState.copyWith(
      status: OrbitConnectionStatus.connectedUnpaired,
      host: host,
      port: port,
      errorMessage: null,
    );
    _mockEvents.add(const OrbitEvent(
      event: 'welcome',
      payload: {'version': '0.1.0'},
    ));
  }

  @override
  void markPaired(String deviceId) {
    _mockState = _mockState.copyWith(
      status: OrbitConnectionStatus.paired,
      deviceId: deviceId,
    );
  }

  @override
  void markUnpaired() {
    _mockState = _mockState.copyWith(
      status: OrbitConnectionStatus.connectedUnpaired,
      deviceId: null,
    );
  }

  @override
  Future<int> sendPing() async {
    return 10;
  }

  @override
  Future<OrbitResponse> sendRequest(
    String action, {
    Map<String, dynamic>? payload,
    Duration? timeout,
  }) async {
    if (action == 'system.info') {
      return OrbitResponse(
        id: 'mock-sys-id',
        action: 'system.info',
        success: true,
        payload: customSystemInfoPayload,
      );
    }
    if (action == 'session.resume') {
      return const OrbitResponse(
        id: 'mock-resume-id',
        action: 'session.resume',
        success: true,
        payload: {'resumed': true},
      );
    }
    if (action == 'pairing.verify') {
      return const OrbitResponse(
        id: 'mock-pair-id',
        action: 'pairing.verify',
        success: true,
        payload: {'paired': true, 'deviceId': 'dev_mock_123'},
      );
    }
    return const OrbitResponse(
      id: 'mock-resp-id',
      action: 'mock',
      success: true,
      payload: {'resumed': true},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 09 — Tailscale & Global Access Tests', () {
    test('1. TailscaleInfoModel JSON parsing and state classification', () {
      // Connected & Ready
      final readyJson = {
        'installed': true,
        'state': 'connected',
        'ip': '100.115.92.2',
        'device_name': 'dev-workstation',
      };
      final readyModel = TailscaleInfoModel.fromJson(readyJson);
      expect(readyModel.installed, isTrue);
      expect(readyModel.state, 'connected');
      expect(readyModel.ip, '100.115.92.2');
      expect(readyModel.deviceName, 'dev-workstation');
      expect(readyModel.isReady, isTrue);
      expect(readyModel.isSetupRequired, isFalse);
      expect(readyModel.isUnavailable, isFalse);

      // Needs login / Stopped -> Setup Required
      final setupJson = {
        'installed': true,
        'state': 'needs_login',
        'ip': null,
        'device_name': null,
      };
      final setupModel = TailscaleInfoModel.fromJson(setupJson);
      expect(setupModel.installed, isTrue);
      expect(setupModel.isReady, isFalse);
      expect(setupModel.isSetupRequired, isTrue);
      expect(setupModel.isUnavailable, isFalse);

      // Not installed -> Unavailable
      final unavailJson = {
        'installed': false,
        'state': 'not_installed',
        'ip': null,
        'device_name': null,
      };
      final unavailModel = TailscaleInfoModel.fromJson(unavailJson);
      expect(unavailModel.installed, isFalse);
      expect(unavailModel.isReady, isFalse);
      expect(unavailModel.isSetupRequired, isFalse);
      expect(unavailModel.isUnavailable, isTrue);
    });

    test('2. SystemInfo model parses optional tailscale field', () {
      final sysJson = {
        'hostname': 'Omarchy-Box',
        'os': 'Linux',
        'os_version': '6.8.0',
        'architecture': 'x86_64',
        'network': [
          {'interface_name': 'eth0', 'ip': '192.168.1.100'}
        ],
        'primary_ip': '192.168.1.100',
        'tailscale': {
          'installed': true,
          'state': 'connected',
          'ip': '100.100.10.5',
          'device_name': 'omarchy-box.tailnet.ts.net',
        },
      };

      final sys = SystemInfo.fromJson(sysJson);
      expect(sys.hostname, 'Omarchy-Box');
      expect(sys.tailscale, isNotNull);
      expect(sys.tailscale!.ip, '100.100.10.5');
      expect(sys.tailscale!.isReady, isTrue);

      // SystemInfo without tailscale key (backward compatibility)
      final sysJsonLegacy = {
        'hostname': 'Omarchy-Box',
        'os': 'Linux',
        'os_version': '6.8.0',
        'architecture': 'x86_64',
        'network': [],
      };
      final sysLegacy = SystemInfo.fromJson(sysJsonLegacy);
      expect(sysLegacy.tailscale, isNull);
    });

    test('3. PairedDeviceRecord supports tailscaleAddress and lastUsedPath serialization', () {
      const record = PairedDeviceRecord(
        deviceId: 'device-id-1',
        pcDisplayName: 'Workstation',
        pcAddress: '192.168.1.50',
        pcPort: 4371,
        mobileDisplayName: 'My Pixel',
        pairedAt: 1700000000,
        tailscaleAddress: '100.64.0.1',
        lastUsedPath: 'tailscale',
      );

      final jsonMap = record.toJson();
      expect(jsonMap['tailscaleAddress'], '100.64.0.1');
      expect(jsonMap['lastUsedPath'], 'tailscale');

      final reconstructed = PairedDeviceRecord.fromJson(jsonMap);
      expect(reconstructed.pcDisplayName, 'Workstation');
      expect(reconstructed.pcAddress, '192.168.1.50');
      expect(reconstructed.tailscaleAddress, '100.64.0.1');
      expect(reconstructed.lastUsedPath, 'tailscale');

      // Legacy record with missing fields
      final legacyJson = {
        'deviceId': 'legacy-id',
        'pcDisplayName': 'Legacy PC',
        'pcAddress': '192.168.1.20',
        'pcPort': 4371,
        'mobileDisplayName': 'Legacy Phone',
        'pairedAt': 1600000000,
      };
      final legacy = PairedDeviceRecord.fromJson(legacyJson);
      expect(legacy.tailscaleAddress, isNull);
      expect(legacy.lastUsedPath, isNull);
    });

    test('4. OrbitPairingQrPayload parses ts_host from pairing QR payload', () {
      // Standard LAN QR payload
      const qrLan = 'orbit://pair?host=192.168.1.80&port=4371&code=123456';
      final parsedLan = OrbitPairingQrPayload.tryParse(qrLan);
      expect(parsedLan, isNotNull);
      expect(parsedLan!.host, '192.168.1.80');
      expect(parsedLan.port, 4371);
      expect(parsedLan.code, '123456');
      expect(parsedLan.tailscaleHost, isNull);

      // Tailscale dual-path QR payload
      const qrDual =
          'orbit://pair?host=192.168.1.80&port=4371&code=987654&ts_host=100.120.10.5';
      final parsedDual = OrbitPairingQrPayload.tryParse(qrDual);
      expect(parsedDual, isNotNull);
      expect(parsedDual!.host, '192.168.1.80');
      expect(parsedDual.tailscaleHost, '100.120.10.5');
      expect(parsedDual.port, 4371);
      expect(parsedDual.code, '987654');
    });

    test('5. ConnectionManager path switching and fallback behavior', () async {
      final mockStorage = MockLocalStorage();
      final mockClient = MockWebSocketClient();
      final manager = ConnectionManager(mockClient, mockStorage);

      // Default preferredPath is null (LAN first by default)
      expect(manager.state.preferredPath, isNull);

      // Setup paired device with both LAN and Tailscale
      await mockStorage.savePairedDevice(PairedDeviceRecord(
        deviceId: 'dev-1',
        pcDisplayName: 'Test Workstation',
        pcAddress: '192.168.1.100',
        pcPort: 4371,
        mobileDisplayName: 'My Phone',
        pairedAt: DateTime.now().millisecondsSinceEpoch,
        tailscaleAddress: '100.100.5.5',
      ));

      // 5a. Primary LAN connects successfully
      final ok = await manager.connectOptimal(
        lanHost: '192.168.1.100',
        tsHost: '100.100.5.5',
        port: 4371,
      );
      expect(ok, isTrue);
      expect(manager.state.activePath, ConnectionPathType.localLan);
      expect(mockClient.lastConnectedHost, '192.168.1.100');

      // 5b. Primary LAN fails, automatic fallback to Tailscale
      mockClient.failNextConnect = true; // LAN will fail
      final fallbackOk = await manager.connectOptimal(
        lanHost: '192.168.1.100',
        tsHost: '100.100.5.5',
        port: 4371,
      );
      expect(fallbackOk, isTrue);
      expect(manager.state.activePath, ConnectionPathType.tailscale);
      expect(mockClient.lastConnectedHost, '100.100.5.5');

      // Check persisted lastUsedPath
      final saved = await mockStorage.getPairedDevice();
      expect(saved?.lastUsedPath, 'tailscale');

      // 5c. User explicitly selects Tailscale path
      manager.setPreferredPath(ConnectionPathType.tailscale);
      expect(manager.state.preferredPath, ConnectionPathType.tailscale);

      final directTsOk = await manager.connectOptimal(
        lanHost: '192.168.1.100',
        tsHost: '100.100.5.5',
        port: 4371,
      );
      expect(directTsOk, isTrue);
      expect(mockClient.lastConnectedHost, '100.100.5.5');
      expect(manager.state.activePath, ConnectionPathType.tailscale);
    });

    testWidgets('6. ConnectionScreen renders path selector and recent devices with Tailscale',
        (tester) async {
      final mockStorage = MockLocalStorage();
      await mockStorage.savePairedDevice(PairedDeviceRecord(
        deviceId: 'studio-pc',
        pcDisplayName: 'Studio PC',
        pcAddress: '192.168.1.42',
        pcPort: 4371,
        mobileDisplayName: 'My Phone',
        pairedAt: DateTime.now().millisecondsSinceEpoch,
        tailscaleAddress: '100.80.20.10',
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageProvider.overrideWithValue(mockStorage),
          ],
          child: const MaterialApp(
            home: ConnectionScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Path selector options rendered
      expect(find.text('Connection:'), findsOneWidget);
      expect(find.text('Local Network'), findsOneWidget);
      expect(find.text('Tailscale'), findsWidgets);

      // Recent device card rendered with both paths
      expect(find.text('Studio PC'), findsOneWidget);
      expect(find.textContaining('LAN: 192.168.1.42'), findsOneWidget);
      expect(find.textContaining('Tailscale: 100.80.20.10'), findsOneWidget);

      // Tap 'Tailscale' path selector
      await tester.tap(find.text('Tailscale').first);
      await tester.pumpAndSettle();

      // Form now shows Tailscale Address label
      expect(find.text('Tailscale Address'), findsOneWidget);
    });

    testWidgets('7. DashboardScreen renders connection badge and environment status',
        (tester) async {
      final mockStorage = MockLocalStorage();
      final mockClient = MockWebSocketClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageProvider.overrideWithValue(mockStorage),
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: DashboardScreen(
              host: '100.115.92.2',
              port: 4371,
            ),
          ),
        ),
      );
      await tester.pump();

      // Dashboard indicates Tailscale connection in header and card
      expect(find.textContaining('Tailscale'), findsWidgets);
    });

    test('8. Existing paired device with no tailscaleAddress reconnects over LAN and gets enriched from system.info without re-pairing', () async {
      final mockStorage = MockLocalStorage();
      final mockClient = MockWebSocketClient();

      // Device was previously paired over LAN with tailscaleAddress == null
      await mockStorage.savePairedDevice(const PairedDeviceRecord(
        deviceId: 'paired-lan-dev-42',
        pcDisplayName: 'Developer PC (192.168.100.4)',
        pcAddress: '192.168.100.4',
        pcPort: 4371,
        mobileDisplayName: 'My Phone',
        pairedAt: 1700000000,
        tailscaleAddress: null,
      ));

      final controller = ConnectionController(mockClient, mockStorage);
      await Future.delayed(const Duration(milliseconds: 10));

      // Reconnect over LAN
      final ok = await controller.connect(
        customHost: '192.168.100.4',
        customPort: 4371,
        specificPath: ConnectionPathType.localLan,
      );

      expect(ok, isTrue);

      // Verify controller state was enriched with fresh Tailscale address and hostname
      expect(controller.state.savedPairedDevice?.tailscaleAddress, '100.83.227.27');
      expect(controller.state.savedPairedDevice?.pcDisplayName, 'Aburaya');
      expect(controller.state.tailscaleHost, '100.83.227.27');

      // Verify storage was persisted with enriched record
      final savedRecord = await mockStorage.getPairedDevice();
      expect(savedRecord, isNotNull);
      expect(savedRecord!.deviceId, 'paired-lan-dev-42'); // device ID unchanged, NOT re-paired
      expect(savedRecord.tailscaleAddress, '100.83.227.27');
      expect(savedRecord.tailscaleState, 'connected');
      expect(savedRecord.pcDisplayName, 'Aburaya');
      expect(savedRecord.lastUsedPath, 'localLan');
    });

    test('9. PairingController.verifyPairing enriches paired record with fresh system.info Tailscale IP', () async {
      final mockStorage = MockLocalStorage();
      final mockClient = MockWebSocketClient();
      final pairingCtrl = PairingController(mockClient, mockStorage);

      pairingCtrl.setCode('889900');
      final ok = await pairingCtrl.verifyPairing('192.168.100.4', 4371);
      expect(ok, isTrue);

      final saved = await mockStorage.getPairedDevice();
      expect(saved, isNotNull);
      expect(saved!.tailscaleAddress, '100.83.227.27');
      expect(saved.tailscaleState, 'connected');
      expect(saved.pcDisplayName, 'Aburaya');
    });

    test('10. refreshDeviceInfo probes Desktop, enriches PairedDeviceRecord and updates UI state', () async {
      final mockStorage = MockLocalStorage();
      final mockClient = MockWebSocketClient();

      await mockStorage.savePairedDevice(const PairedDeviceRecord(
        deviceId: 'dev-refresh-test',
        pcDisplayName: 'Old Name',
        pcAddress: '192.168.100.4',
        pcPort: 4371,
        mobileDisplayName: 'My Phone',
        pairedAt: 1700000000,
        tailscaleAddress: null,
      ));

      // Emulate that the client is currently connected & paired
      mockClient.setMockState(const OrbitConnectionState(
        status: OrbitConnectionStatus.paired,
        deviceId: 'mock-device-id-12345',
        host: '192.168.100.4',
        port: 4371,
      ));

      final controller = ConnectionController(mockClient, mockStorage);
      await Future.delayed(const Duration(milliseconds: 10));

      final refreshed = await controller.refreshDeviceInfo(showLoading: true);
      expect(refreshed, isTrue);

      expect(controller.state.savedPairedDevice?.tailscaleAddress, '100.83.227.27');
      expect(controller.state.savedPairedDevice?.pcDisplayName, 'Aburaya');
      expect(controller.state.tailscaleHost, '100.83.227.27');

      final saved = await mockStorage.getPairedDevice();
      expect(saved?.tailscaleAddress, '100.83.227.27');
      expect(saved?.tailscaleState, 'connected');
    });

    testWidgets('11. ConnectionScreen transitions from Not configured to Ready and displays both paths',
        (tester) async {
      final mockStorage = MockLocalStorage();
      final mockClient = MockWebSocketClient();

      // Initially paired over LAN without Tailscale
      await mockStorage.savePairedDevice(const PairedDeviceRecord(
        deviceId: 'pc-unconfigured',
        pcDisplayName: 'Developer PC',
        pcAddress: '192.168.100.4',
        pcPort: 4371,
        mobileDisplayName: 'My Phone',
        pairedAt: 1700000000,
        tailscaleAddress: null,
      ));

      // Emulate connected & paired so live refresh works
      mockClient.setMockState(const OrbitConnectionState(
        status: OrbitConnectionStatus.paired,
        deviceId: 'mock-device-id-12345',
        host: '192.168.100.4',
        port: 4371,
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageProvider.overrideWithValue(mockStorage),
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: ConnectionScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Before refresh: Tailscale card / selector shows 'Not configured'
      expect(find.text('Not configured'), findsWidgets);
      expect(find.text('Local Network Only'), findsOneWidget);

      // Select Tailscale path tab to display Tailscale configuration card
      await tester.tap(find.text('Tailscale').first);
      await tester.pumpAndSettle();

      // Now trigger Check Again or tap refresh
      final checkAgainFinder = find.widgetWithText(OutlinedButton, 'Check Again');
      expect(checkAgainFinder, findsOneWidget);
      await tester.ensureVisible(checkAgainFinder);
      await tester.pumpAndSettle();
      await tester.tap(checkAgainFinder);
      await tester.pumpAndSettle();

      // After refresh: Tailscale status is Ready with real IP 100.83.227.27
      expect(find.text('Ready'), findsWidgets);
      expect(find.text('100.83.227.27'), findsWidgets);
      expect(find.text('Tailscale Ready'), findsOneWidget);

      // Both LAN and Tailscale paths are available
      expect(find.text('Local Network'), findsOneWidget);
      expect(find.text('Available'), findsWidgets);
    });

    test('12. Automatic LAN unreachable fallback to Tailscale in ConnectionController', () async {
      final mockStorage = MockLocalStorage();
      final mockClient = MockWebSocketClient();

      await mockStorage.savePairedDevice(const PairedDeviceRecord(
        deviceId: 'dev-fallback-test',
        pcDisplayName: 'Developer PC',
        pcAddress: '192.168.100.4',
        pcPort: 4371,
        mobileDisplayName: 'My Phone',
        pairedAt: 1700000000,
        tailscaleAddress: '100.83.227.27',
      ));

      final controller = ConnectionController(mockClient, mockStorage);
      await Future.delayed(const Duration(milliseconds: 10));

      // Make next connect attempt (LAN) fail
      mockClient.failNextConnect = true;

      // Connect with localLan path
      final ok = await controller.connect(
        customHost: '192.168.100.4',
        customPort: 4371,
        specificPath: ConnectionPathType.localLan,
      );

      expect(ok, isTrue);
      // Fallback connected to Tailscale IP
      expect(mockClient.lastConnectedHost, '100.83.227.27');
      expect(controller.state.selectedPath, ConnectionPathType.tailscale);
    });
  });
}
