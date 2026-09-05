import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit_mobile/core/networking/orbit_websocket_client.dart';
import 'package:orbit_mobile/core/providers.dart';
import 'package:orbit_mobile/features/ai/controllers/ai_permission_controller.dart';
import 'package:orbit_mobile/features/ai/models/ai_permission_models.dart';
import 'package:orbit_mobile/features/ai/widgets/permission_approval_card.dart';
import 'package:orbit_mobile/features/files/views/markdown_viewer_screen.dart';
import 'package:orbit_mobile/protocol/messages/orbit_response.dart';
import 'package:orbit_mobile/protocol/models/file_models.dart';

class MockOrbitWebSocketClient extends OrbitWebSocketClient {
  final List<Map<String, dynamic>> sentRequests = [];
  OrbitResponse? nextResponse;

  @override
  Future<OrbitResponse> sendRequest(
    String action, {
    Map<String, dynamic>? payload,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    sentRequests.add({
      'action': action,
      'payload': payload,
    });
    if (nextResponse != null) {
      return nextResponse!;
    }
    return OrbitResponse(
      id: 'mock_resp',
      action: action,
      success: true,
      payload: {},
    );
  }
}

void main() {
  group('Orbit Milestone 10 — Markdown Viewer Tests', () {
    test('1. Markdown file category detection', () {
      expect(FileCategory.fromExtension('README.md'), FileCategory.markdown);
      expect(FileCategory.fromExtension('CHANGELOG.markdown'), FileCategory.markdown);
      expect(FileCategory.fromExtension('docs/intro.mdx'), FileCategory.markdown);
      expect(FileCategory.fromExtension('README.MD'), FileCategory.markdown);
      expect(FileCategory.fromExtension('src/main.rs'), FileCategory.code);
      expect(FileCategory.fromExtension('notes.txt'), FileCategory.text);
      expect(FileCategory.fromExtension('logo.png'), FileCategory.image);
    });

    testWidgets('2. MarkdownViewerScreen renders header, badges, and toggle', (tester) async {
      final mockClient = MockOrbitWebSocketClient();
      mockClient.nextResponse = OrbitResponse(
        id: '1',
        action: 'files.read',
        success: true,
        payload: {
          'path': '/workspace/README.md',
          'content': '# Orbit Agent\n\nA powerful desktop daemon.\n\n```bash\nflutter run\n```\n',
          'encoding': 'utf8',
          'size': 68,
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: MarkdownViewerScreen(
              path: '/workspace/README.md',
              fileName: 'README.md',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify file title and badge
      expect(find.text('README.md'), findsOneWidget);
      expect(find.text('MARKDOWN'), findsOneWidget);
      expect(find.text('/workspace/README.md'), findsOneWidget);

      // Verify preview / source toggle buttons
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);

      // Verify actions: Ask Orbit AI, Copy
      expect(find.byTooltip('Ask Orbit AI'), findsOneWidget);
      expect(find.byTooltip('Copy all'), findsOneWidget);

      // Verify Rendered markdown content is present
      expect(find.text('Orbit Agent'), findsOneWidget);
      expect(find.text('A powerful desktop daemon.'), findsOneWidget);

      // Switch to Source mode
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();

      expect(find.text('Raw text'), findsOneWidget);
      expect(find.textContaining('# Orbit Agent'), findsOneWidget);
    });
  });

  group('Orbit Milestone 10 — File Search Tests', () {
    test('3. SearchFileResult and FileSearchResult serialization', () {
      final jsonMap = {
        'root': '/home/user/orbit',
        'query': 'terminal',
        'mode': 'content',
        'totalMatches': 2,
        'truncated': false,
        'results': [
          {
            'path': '/home/user/orbit/src/terminal.rs',
            'name': 'terminal.rs',
            'isDirectory': false,
            'line': 42,
            'snippet': 'let term = Terminal::new();',
          },
          {
            'path': '/home/user/orbit/docs/terminal.md',
            'name': 'terminal.md',
            'isDirectory': false,
            'line': 1,
            'snippet': '# Terminal Architecture',
          },
        ],
      };

      final searchResult = FileSearchResult.fromJson(jsonMap);
      expect(searchResult.root, '/home/user/orbit');
      expect(searchResult.query, 'terminal');
      expect(searchResult.mode, 'content');
      expect(searchResult.totalMatches, 2);
      expect(searchResult.truncated, false);
      expect(searchResult.results.length, 2);

      final first = searchResult.results.first;
      expect(first.name, 'terminal.rs');
      expect(first.line, 42);
      expect(first.snippet, 'let term = Terminal::new();');

      final second = searchResult.results[1];
      expect(second.name, 'terminal.md');
      expect(FileCategory.fromExtension(second.name), FileCategory.markdown);
    });
  });

  group('Orbit Milestone 10 — AI Permission Approval Tests', () {
    test('4. AiPermissionRequest model parsing and risk classification', () {
      final reqJson = {
        'permissionId': 'perm_001',
        'taskId': 'task_abc',
        'deviceId': 'mobile_dev_1',
        'tool': 'bash',
        'action': 'run command',
        'target': 'flutter analyze',
        'patterns': ['flutter analyze*'],
        'projectPath': '/home/user/Projects/orbit',
        'risk': 'medium',
        'state': 'pending',
        'createdAt': 1700000000,
        'timeoutAt': 1700000300,
      };

      final req = AiPermissionRequest.fromJson(reqJson);
      expect(req.permissionId, 'perm_001');
      expect(req.taskId, 'task_abc');
      expect(req.tool, 'bash');
      expect(req.target, 'flutter analyze');
      expect(req.risk, AiPermissionRisk.medium);
      expect(req.isHighRisk, false);
      expect(req.isPending, true);

      final highRiskJson = Map<String, dynamic>.from(reqJson)
        ..['target'] = 'rm -rf node_modules'
        ..['risk'] = 'high';

      final highRiskReq = AiPermissionRequest.fromJson(highRiskJson);
      expect(highRiskReq.isHighRisk, true);
    });

    testWidgets('5. PermissionApprovalCard renders details and handles Allow/Deny', (tester) async {
      final mockClient = MockOrbitWebSocketClient();
      final req = AiPermissionRequest(
        permissionId: 'perm_test_1',
        taskId: 'task_1',
        deviceId: 'dev_1',
        tool: 'bash',
        action: 'run command',
        target: 'flutter test',
        patterns: ['flutter test'],
        projectPath: '/projects/orbit',
        risk: AiPermissionRisk.medium,
        state: AiPermissionState.pending,
        createdAt: 1700000000,
        timeoutAt: 1700000300,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PermissionApprovalCard(request: req),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check card UI elements
      expect(find.text('Permission Required'), findsOneWidget);
      expect(find.text('\$ flutter test'), findsOneWidget);
      expect(find.text('/projects/orbit'), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Always Allow for this session'), findsOneWidget);

      // Tap Allow button
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      // Verify request sent over WebSocket
      expect(mockClient.sentRequests.length, 1);
      expect(mockClient.sentRequests.first['action'], 'ai.permission.resolve');
      expect(mockClient.sentRequests.first['payload']['permissionId'], 'perm_test_1');
      expect(mockClient.sentRequests.first['payload']['decision'], 'once');
    });

    testWidgets('6. Destructive actions forbid Always Allow in PermissionApprovalCard', (tester) async {
      final mockClient = MockOrbitWebSocketClient();
      final destructiveReq = AiPermissionRequest(
        permissionId: 'perm_test_dest',
        taskId: 'task_2',
        deviceId: 'dev_1',
        tool: 'bash',
        action: 'run command',
        target: 'rm -rf /projects/orbit/build',
        patterns: ['rm -rf*'],
        projectPath: '/projects/orbit',
        risk: AiPermissionRisk.high,
        state: AiPermissionState.pending,
        createdAt: 1700000000,
        timeoutAt: 1700000300,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PermissionApprovalCard(request: destructiveReq),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // High risk badge must be visible
      expect(find.text('HIGH RISK'), findsOneWidget);
      expect(find.textContaining('destructive action'), findsOneWidget);

      // Always Allow MUST NOT be shown for destructive actions!
      expect(find.text('Always Allow for this session'), findsNothing);

      // Deny and Allow must be present
      expect(find.text('Deny'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);

      // Tap Deny button
      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();

      expect(mockClient.sentRequests.length, 1);
      expect(mockClient.sentRequests.first['action'], 'ai.permission.resolve');
      expect(mockClient.sentRequests.first['payload']['permissionId'], 'perm_test_dest');
      expect(mockClient.sentRequests.first['payload']['decision'], 'reject');
    });

    test('7. AiPermissionController state machine and task filtering', () async {
      final mockClient = MockOrbitWebSocketClient();
      final controller = AiPermissionController(mockClient);

      // Initially empty
      expect(controller.state.pendingRequests.isEmpty, true);

      // Simulate ai.permission.requested event
      final req1 = {
        'permissionId': 'p1',
        'taskId': 'task_A',
        'deviceId': 'd1',
        'tool': 'bash',
        'action': 'run',
        'target': 'git status',
        'projectPath': '/orbit',
        'risk': 'low',
        'state': 'pending',
        'createdAt': 100,
        'timeoutAt': 400,
      };
      final req2 = {
        'permissionId': 'p2',
        'taskId': 'task_B',
        'deviceId': 'd1',
        'tool': 'bash',
        'action': 'run',
        'target': 'git push',
        'projectPath': '/orbit',
        'risk': 'medium',
        'state': 'pending',
        'createdAt': 100,
        'timeoutAt': 400,
      };

      mockClient.events; // initialize stream
      controller.state = controller.state.copyWith(
        pendingRequests: [
          AiPermissionRequest.fromJson(req1),
          AiPermissionRequest.fromJson(req2),
        ],
      );

      // Verify multiple simultaneous requests preserved
      expect(controller.state.pendingRequests.length, 2);

      // Verify task filtering
      final taskAReqs = controller.pendingRequestsForTask('task_A');
      expect(taskAReqs.length, 1);
      expect(taskAReqs.first.permissionId, 'p1');

      final taskBReqs = controller.pendingRequestsForTask('task_B');
      expect(taskBReqs.length, 1);
      expect(taskBReqs.first.permissionId, 'p2');

      // Resolve request p1
      await controller.resolvePermission('p1', 'once');
      expect(controller.state.pendingRequests.length, 1);
      expect(controller.state.pendingRequests.first.permissionId, 'p2');

      controller.dispose();
    });
  });
}
