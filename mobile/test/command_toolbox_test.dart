import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/core/networking/orbit_websocket_client.dart';
import 'package:orbit_mobile/core/providers.dart';
import 'package:orbit_mobile/features/terminal/models/command_tool.dart';
import 'package:orbit_mobile/features/terminal/views/command_toolbox_screen.dart';
import 'package:orbit_mobile/features/terminal/views/terminal_screen.dart';
import 'package:orbit_mobile/protocol/messages/orbit_response.dart';

class MockWebSocketClient extends OrbitWebSocketClient {
  final List<String> sentActions = [];
  final List<dynamic> sentPayloads = [];

  @override
  Future<OrbitResponse> sendRequest(
    String action, {
    Map<String, dynamic>? payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    sentActions.add(action);
    sentPayloads.add(payload);

    if (action == 'terminal.list') {
      return OrbitResponse(
        id: '1',
        action: action,
        success: true,
        payload: {
          'sessions': [
            {
              'sessionId': 'term_toolbox_1',
              'status': 'running',
              'cwd': '/home/developer',
              'shell': '/bin/bash',
              'rows': 24,
              'cols': 80,
              'createdAt': 123456,
              'lastActivityAt': 123456,
              'ownerDeviceId': 'test_device',
            }
          ]
        },
      );
    } else if (action == 'terminal.history') {
      return OrbitResponse(
        id: '2',
        action: action,
        success: true,
        payload: {
          'sessionId': 'term_toolbox_1',
          'data': 'Orbit Terminal Ready\r\n',
        },
      );
    } else if (action == 'terminal.input') {
      return OrbitResponse(
        id: '3',
        action: action,
        success: true,
        payload: {'success': true},
      );
    }

    return OrbitResponse(id: '99', action: action, success: true);
  }
}

void main() {
  group('CommandTool Catalog & Model Tests', () {
    test('1. Catalog contains OS-filtered tools', () {
      final allTools = CommandToolCatalog.tools;
      expect(allTools, isNotEmpty);

      // Windows catalog
      final windowsTools = CommandToolCatalog.forOs(TargetOs.windows);
      final winToolIds = windowsTools.map((t) => t.id).toList();
      expect(winToolIds, contains('windows_services'));
      expect(winToolIds, isNot(contains('macos_caffeinate')));
      expect(winToolIds, isNot(contains('linux_systemd_failed')));

      // Linux catalog
      final linuxTools = CommandToolCatalog.forOs(TargetOs.linux);
      final linuxToolIds = linuxTools.map((t) => t.id).toList();
      expect(linuxToolIds, contains('linux_systemd_failed'));
      expect(linuxToolIds, isNot(contains('windows_services')));
      expect(linuxToolIds, isNot(contains('macos_caffeinate')));

      // macOS catalog
      final macTools = CommandToolCatalog.forOs(TargetOs.macos);
      final macToolIds = macTools.map((t) => t.id).toList();
      expect(macToolIds, contains('macos_caffeinate'));
      expect(macToolIds, contains('macos_restart_ui'));
      expect(macToolIds, isNot(contains('windows_services')));
      expect(macToolIds, isNot(contains('linux_systemd_failed')));
    });

    test('2. Command parameter interpolation and OS adaptation work accurately', () {
      final pingTool = CommandToolCatalog.tools.firstWhere((t) => t.id == 'ping_host');
      final linuxPing = pingTool.buildCommand(TargetOs.linux, {'host': '1.1.1.1'});
      expect(linuxPing, 'ping -c 4 1.1.1.1');
      final winPing = pingTool.buildCommand(TargetOs.windows, {'host': '1.1.1.1'});
      expect(winPing, 'ping -n 4 1.1.1.1');

      final killTool = CommandToolCatalog.tools.firstWhere((t) => t.id == 'kill_pid');
      final linuxKill = killTool.buildCommand(TargetOs.linux, {'pid': '4567'});
      expect(linuxKill, 'kill -9 4567');
      final winKill = killTool.buildCommand(TargetOs.windows, {'pid': '4567'});
      expect(winKill, 'taskkill /PID 4567 /F');

      final sysinfoTool = CommandToolCatalog.tools.firstWhere((t) => t.id == 'sysinfo');
      expect(sysinfoTool.buildCommand(TargetOs.windows), 'systeminfo');
      expect(sysinfoTool.buildCommand(TargetOs.linux), 'uname -a && hostnamectl');
      expect(sysinfoTool.buildCommand(TargetOs.macos), 'sw_vers && uname -a');
    });

    test('3. Danger classification is correctly tagged', () {
      final restartTool = CommandToolCatalog.tools.firstWhere((t) => t.id == 'restart_computer');
      expect(restartTool.dangerLevel, DangerLevel.destructive);
      expect(restartTool.executionType, CommandExecutionType.confirmation);

      final gitStatusTool = CommandToolCatalog.tools.firstWhere((t) => t.id == 'git_status');
      expect(gitStatusTool.dangerLevel, DangerLevel.safe);
      expect(gitStatusTool.executionType, CommandExecutionType.instant);
    });
  });

  group('CommandToolboxScreen UI & Execution Tests', () {
    testWidgets('1. Renders OS badge, search bar, categories, and tools', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockWebSocketClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: CommandToolboxScreen(initialOs: 'linux'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title & OS badge
      expect(find.text('COMMAND TOOLBOX'), findsOneWidget);
      expect(find.text('LINUX'), findsOneWidget);

      // Verify search field
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search commands & tools...'), findsOneWidget);

      // Verify category chips
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Power'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Network'), findsOneWidget);

      // Verify some tool cards are visible
      expect(find.text('System Information'), findsOneWidget);
      expect(find.text('Shutdown Computer'), findsOneWidget);
    });

    testWidgets('2. Search filtering narrows visible commands', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockWebSocketClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: CommandToolboxScreen(initialOs: 'linux'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter search text
      await tester.enterText(find.byType(TextField), 'ping');
      await tester.pumpAndSettle();

      // Should show Ping Host
      expect(find.text('Ping Host'), findsOneWidget);
      // Other unrelated tools should be filtered out
      expect(find.text('System Information'), findsNothing);
      expect(find.text('Shutdown Computer'), findsNothing);
    });

    testWidgets('3. Instant command executes via terminalController.sendInput', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockWebSocketClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: CommandToolboxScreen(initialOs: 'linux'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Filter to Developer to find Git Status easily
      await tester.tap(find.text('Developer'));
      await tester.pumpAndSettle();

      expect(find.text('Git Status'), findsOneWidget);

      // Tap on Git Status card
      await tester.tap(find.text('Git Status'));
      await tester.pumpAndSettle();

      // Verify snackbar appears with executed message and Open Terminal button
      expect(find.textContaining('Executed: git status'), findsOneWidget);
      expect(find.text('Open Terminal'), findsOneWidget);

      // Verify mockClient received terminal.input action
      expect(mockClient.sentActions, contains('terminal.input'));
      final inputPayload = mockClient.sentPayloads.lastWhere((p) => p != null && p['data'] != null) as Map<String, dynamic>;
      expect(inputPayload['data'], 'git status\r');
    });

    testWidgets('4. Parameterized command opens form and executes formatted command', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockWebSocketClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: CommandToolboxScreen(initialOs: 'linux'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Network category
      await tester.tap(find.text('Network'));
      await tester.pumpAndSettle();

      expect(find.text('Ping Host'), findsOneWidget);

      // Tap on Ping Host card
      await tester.tap(find.text('Ping Host'));
      await tester.pumpAndSettle();

      // Form dialog should be visible
      expect(find.text('Target Host / IP'), findsOneWidget);
      expect(find.text('Run Ping Host'), findsOneWidget);

      // Tap Run Ping Host in modal
      await tester.tap(find.text('Run Ping Host'));
      await tester.pumpAndSettle();

      // Should show Executed snackbar
      expect(find.textContaining('Executed: ping -c 4 google.com'), findsOneWidget);

      // Verify terminal input sent
      expect(mockClient.sentActions, contains('terminal.input'));
      final inputPayload = mockClient.sentPayloads.lastWhere((p) => p != null && p['data'] != null) as Map<String, dynamic>;
      expect(inputPayload['data'], 'ping -c 4 google.com\r');
    });

    testWidgets('5. Restart computer prompts with confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockWebSocketClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: CommandToolboxScreen(initialOs: 'linux'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Power category
      await tester.tap(find.text('Power'));
      await tester.pumpAndSettle();

      expect(find.text('Restart Computer'), findsOneWidget);

      // Tap Restart Computer card
      await tester.tap(find.text('Restart Computer'));
      await tester.pumpAndSettle();

      // Confirm dialog should appear
      expect(find.text('Confirm & Run'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Confirm & Run'), findsNothing);

      // Tap again and confirm
      await tester.tap(find.text('Restart Computer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm & Run'));
      await tester.pumpAndSettle();

      expect(mockClient.sentActions, contains('terminal.input'));
      final inputPayload = mockClient.sentPayloads.lastWhere((p) => p != null && p['data'] != null) as Map<String, dynamic>;
      expect(inputPayload['data'], 'reboot\r');
    });

    testWidgets('6. Shutdown timer UI offers presets and schedules cancellation banner', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockWebSocketClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: CommandToolboxScreen(initialOs: 'linux'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Power category
      await tester.tap(find.text('Power'));
      await tester.pumpAndSettle();

      expect(find.text('Shutdown Computer'), findsOneWidget);

      // Tap Shutdown Computer card
      await tester.tap(find.text('Shutdown Computer'));
      await tester.pumpAndSettle();

      // Verify timer options
      expect(find.text('WHEN SHOULD THIS PC SHUT DOWN?'), findsOneWidget);
      expect(find.text('Immediately'), findsOneWidget);
      expect(find.text('5 minutes'), findsOneWidget);
      expect(find.text('10 minutes'), findsOneWidget);

      // Tap '10 minutes'
      await tester.tap(find.text('10 minutes'));
      await tester.pumpAndSettle();

      // Tap Schedule Shutdown button
      await tester.tap(find.text('Schedule Shutdown'));
      await tester.pumpAndSettle();

      // Verify command sent
      expect(mockClient.sentActions, contains('terminal.input'));
      final inputPayload = mockClient.sentPayloads.lastWhere((p) => p != null && p['data'] != null) as Map<String, dynamic>;
      expect(inputPayload['data'], 'shutdown +10\r');

      // Schedule banner should now be visible on screen
      expect(find.text('SHUTDOWN SCHEDULED'), findsOneWidget);
      expect(find.text('Cancel Shutdown'), findsOneWidget);

      // Tap Cancel Shutdown
      await tester.tap(find.text('Cancel Shutdown'));
      await tester.pumpAndSettle();

      // Cancel command should be sent
      final cancelPayload = mockClient.sentPayloads.lastWhere((p) => p != null && p['data'] != null) as Map<String, dynamic>;
      expect(cancelPayload['data'], 'shutdown -c\r');
    });

    testWidgets('7. TerminalScreen Tools button opens CommandToolboxScreen', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockWebSocketClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: TerminalScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Tools button exists in AppBar
      final toolsBtn = find.text('Tools');
      expect(toolsBtn, findsOneWidget);

      // Tap Tools button
      await tester.tap(toolsBtn);
      await tester.pumpAndSettle();

      // Command Toolbox should now be shown
      expect(find.text('COMMAND TOOLBOX'), findsOneWidget);
    });
  });
}
