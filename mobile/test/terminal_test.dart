import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/core/networking/orbit_websocket_client.dart';
import 'package:orbit_mobile/core/providers.dart';
import 'package:orbit_mobile/features/terminal/controllers/terminal_controller.dart';
import 'package:orbit_mobile/features/terminal/views/terminal_screen.dart';
import 'package:orbit_mobile/protocol/messages/orbit_response.dart';
import 'package:xterm/xterm.dart' hide TerminalController;

class MockWebSocketClient extends OrbitWebSocketClient {
  final List<String> sentActions = [];
  final List<dynamic> sentPayloads = [];

  List<Map<String, dynamic>>? customSessions;

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
          'sessions': customSessions ??
              [
                {
                  'sessionId': 'term_test_1',
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
          'sessionId': payload?['sessionId'] ?? 'term_test_1',
          'data': 'Orbit Terminal Initialized\r\n',
        },
      );
    } else if (action == 'terminal.create') {
      return OrbitResponse(
        id: '3',
        action: action,
        success: true,
        payload: {
          'sessionId': 'term_test_new',
          'cwd': '/home/developer',
          'shell': '/bin/bash',
          'rows': 24,
          'cols': 80,
        },
      );
    } else if (action == 'terminal.kill') {
      if (customSessions != null && payload != null) {
        final killedId = payload['sessionId'];
        customSessions!.removeWhere((s) => s['sessionId'] == killedId);
      }
      return OrbitResponse(
        id: '4',
        action: action,
        success: true,
        payload: {'success': true},
      );
    }

    return OrbitResponse(id: '99', action: action, success: true);
  }
}

void main() {
  group('Orbit Mobile Terminal UX Overhaul Tests', () {
    test('1. TerminalController initializes with xterm.Terminal and feeds raw ANSI', () async {
      final mockClient = MockWebSocketClient();
      final controller = TerminalController(mockClient);

      // Verify controller starts with active terminal instance
      expect(controller.terminal, isA<Terminal>());

      // Write raw ANSI sequences with color codes directly into terminal
      controller.terminal.write('\x1b[31mRED\x1b[0m \x1b[32mGREEN\x1b[0m\r\n');

      // The terminal buffer should have processed the lines without exception
      expect(controller.terminal.buffer.lines.length, greaterThan(0));

      await Future.delayed(const Duration(milliseconds: 50));
      controller.dispose();
    });

    test('2. Sticky CTRL modifier translates key characters into ASCII control bytes', () async {
      final mockClient = MockWebSocketClient();
      final controller = TerminalController(mockClient);
      await controller.selectSession('term_test_1');

      expect(controller.state.isCtrlActive, false);
      controller.toggleCtrl();
      expect(controller.state.isCtrlActive, true);

      // When CTRL is active and terminal.onOutput fires with 'c', it should send \x03
      controller.terminal.onOutput?.call('c');

      // Sticky CTRL automatically resets after consumed
      expect(controller.state.isCtrlActive, false);
      expect(mockClient.sentActions, contains('terminal.input'));
      final lastPayload = mockClient.sentPayloads.last as Map<String, dynamic>;
      expect(lastPayload['data'], '\x03'); // SIGINT control char

      await Future.delayed(const Duration(milliseconds: 50));
      controller.dispose();
    });

    test('3. Special keyboard shortcuts send authentic control sequences', () async {
      final mockClient = MockWebSocketClient();
      final controller = TerminalController(mockClient);
      await controller.selectSession('term_test_1');

      // Simulate sending Tab (\t)
      await controller.sendInput('\t');
      expect((mockClient.sentPayloads.last as Map<String, dynamic>)['data'], '\t');

      // Simulate sending Esc (\x1b)
      await controller.sendInput('\x1b');
      expect((mockClient.sentPayloads.last as Map<String, dynamic>)['data'], '\x1b');

      // Simulate sending Up Arrow (\x1b[A)
      await controller.sendInput('\x1b[A');
      expect((mockClient.sentPayloads.last as Map<String, dynamic>)['data'], '\x1b[A');

      // Simulate sending Down Arrow (\x1b[B)
      await controller.sendInput('\x1b[B');
      expect((mockClient.sentPayloads.last as Map<String, dynamic>)['data'], '\x1b[B');

      await Future.delayed(const Duration(milliseconds: 50));
      controller.dispose();
    });

    testWidgets('4. TerminalScreen renders real TerminalView and shortcut bar', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
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

      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // TerminalView from xterm package should be present
      expect(find.byType(TerminalView), findsOneWidget);

      // Shortcut bar keys should be rendered
      expect(find.text('CTRL'), findsOneWidget);
      expect(find.text('TAB'), findsOneWidget);
      expect(find.text('ESC'), findsOneWidget);
      expect(find.text('Ctrl+C'), findsOneWidget);
      expect(find.text('Ctrl+D'), findsOneWidget);
      expect(find.text('Ctrl+L'), findsOneWidget);
    });

    test('5. killSession sends terminal.kill and switches active session', () async {
      final mockClient = MockWebSocketClient();
      mockClient.customSessions = [
        {
          'sessionId': 'term_1',
          'status': 'running',
          'cwd': '/home/user',
          'shell': '/bin/bash',
          'rows': 24,
          'cols': 80,
          'createdAt': 100,
          'lastActivityAt': 100,
          'ownerDeviceId': 'dev_1',
        },
        {
          'sessionId': 'term_2',
          'status': 'running',
          'cwd': '/home/user/project',
          'shell': '/bin/bash',
          'rows': 24,
          'cols': 80,
          'createdAt': 200,
          'lastActivityAt': 200,
          'ownerDeviceId': 'dev_1',
        },
      ];

      final controller = TerminalController(mockClient);
      await controller.listSessions();
      expect(controller.state.sessions.length, 2);
      expect(controller.state.activeSessionId, 'term_1');

      // Kill term_1
      await controller.killSession('term_1');

      final killIndex = mockClient.sentActions.indexOf('terminal.kill');
      expect(killIndex, isNot(-1));
      final killPayload = mockClient.sentPayloads[killIndex] as Map<String, dynamic>;
      expect(killPayload['sessionId'], 'term_1');

      // Should automatically switch to term_2
      expect(controller.state.sessions.length, 1);
      expect(controller.state.activeSessionId, 'term_2');

      // Kill the last session
      await controller.killSession('term_2');
      expect(controller.state.sessions.length, 0);
      expect(controller.state.activeSessionId, isNull);

      controller.dispose();
    });

    testWidgets('6. Close button in subheader and tabs shows confirmation dialog and closes session', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockWebSocketClient();
      mockClient.customSessions = [
        {
          'sessionId': 'term_1',
          'status': 'running',
          'cwd': '/home/user',
          'shell': '/bin/bash',
          'rows': 24,
          'cols': 80,
          'createdAt': 100,
          'lastActivityAt': 100,
          'ownerDeviceId': 'dev_1',
        },
        {
          'sessionId': 'term_2',
          'status': 'running',
          'cwd': '/home/user/project',
          'shell': '/bin/bash',
          'rows': 24,
          'cols': 80,
          'createdAt': 200,
          'lastActivityAt': 200,
          'ownerDeviceId': 'dev_1',
        },
      ];

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

      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // Check that both tabs are visible
      expect(find.text('#1 bash'), findsOneWidget);
      expect(find.text('#2 bash'), findsOneWidget);

      // Check that close tooltip in subheader exists
      final closeSubheaderBtn = find.byTooltip('Close Current Terminal');
      expect(closeSubheaderBtn, findsOneWidget);

      // Tap close button in subheader
      await tester.tap(closeSubheaderBtn);
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Close Terminal Session?'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Close
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Verify terminal.kill was dispatched
      expect(mockClient.sentActions, contains('terminal.kill'));
    });
  });
}
