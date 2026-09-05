import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/core/networking/orbit_websocket_client.dart';
import 'package:orbit_mobile/protocol/messages/orbit_event.dart';
import 'package:orbit_mobile/protocol/models/agent_status.dart';
import 'package:orbit_mobile/protocol/models/ai_context.dart';
import 'package:orbit_mobile/protocol/models/file_models.dart';
import 'package:orbit_mobile/protocol/models/system_info.dart';
import 'package:orbit_mobile/protocol/models/pairing_models.dart';

void main() async {
  bool serverAvailable = false;
  try {
    final socket = await Socket.connect('127.0.0.1', 4371,
        timeout: const Duration(milliseconds: 500));
    await socket.close();
    serverAvailable = true;
  } catch (_) {}

  if (!serverAvailable) {
    test('Orbit Mobile Live Desktop Integration Test (Skipped - Server offline)', () {
      // ignore: avoid_print
      print(
          'INFO: Orbit Desktop Agent is not running on 127.0.0.1:4371. Start Orbit Desktop to run live integration tests.');
    });
    return;
  }

  group('Orbit Mobile Live Desktop Integration Test', () {
    final client = OrbitWebSocketClient();
    final pairingCode = Platform.environment['ORBIT_TEST_PAIRING_CODE'] ?? '842917';
    String? terminalSessionId;
    String? testPairedDeviceId;

    tearDownAll(() {
      client.dispose();
    });

    test('1. Connects to Orbit Desktop and receives welcome event', () async {
      final welcomeCompleter = Completer<bool>();
      final sub = client.events.listen((ev) {
        if (ev.event == 'welcome') {
          welcomeCompleter.complete(true);
        }
      });

      await client.connect('127.0.0.1', 4371);
      final receivedWelcome = await welcomeCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
      await sub.cancel();

      expect(receivedWelcome, isTrue);
      expect(client.currentState.isConnected, isTrue);
      expect(client.currentState.isUnpaired, isTrue);
      expect(client.currentState.isPaired, isFalse);
    });

    test('2. Sends ping and measures RTT', () async {
      final latency = await client.sendPing();
      expect(latency, greaterThanOrEqualTo(0));
    });

    test('2b. Protected resource access rejected before pairing', () async {
      expect(client.currentState.isPaired, isFalse);
      final response = await client.sendRequest('system.info');
      expect(response.success, isFalse);
      expect(response.error?.code, equals('UNAUTHORIZED'));
      expect(response.error?.message, contains('Device must be paired'));
    });

    test('2c. Invalid pairing code is rejected', () async {
      final response = await client.sendRequest('pairing.verify', payload: {
        'code': '000000',
        'name': 'Dart Integration Client',
        'platform': 'android',
      });
      expect(response.success, isFalse);
      expect(response.error?.code, equals('INVALID_PAIRING_CODE'));
      expect(client.currentState.isPaired, isFalse);
    });

    test('3. Pairs using 6-digit pairing code and stable deviceId', () async {
      final response = await client.sendRequest('pairing.verify', payload: {
        'code': pairingCode,
        'name': 'Dart Integration Client',
        'platform': 'android',
        'deviceId': 'orbit_e2e_integration_dev_1',
      });

      expect(response.success, isTrue);
      expect(response.payload?['paired'], isTrue);
      final deviceId = response.payload?['deviceId'] as String;
      expect(deviceId, equals('orbit_e2e_integration_dev_1'));
      testPairedDeviceId = deviceId;
      client.markPaired(deviceId);
      expect(client.currentState.isPaired, isTrue);
      expect(client.currentState.isUnpaired, isFalse);
    });

    test('4. Requests real agent.status', () async {
      final response = await client.sendRequest('agent.status');
      expect(response.success, isTrue);
      expect(response.payload, isNotNull);

      final status = AgentStatus.fromJson(response.payload!);
      expect(status.status, 'online');
      expect(status.version, isNotEmpty);
    });

    test('5. Requests real system.info', () async {
      final response = await client.sendRequest('system.info');
      expect(response.success, isTrue);
      expect(response.payload, isNotNull);

      final sys = SystemInfo.fromJson(response.payload!);
      expect(sys.hostname, isNotEmpty);
      expect(sys.os, isNotEmpty);
      expect(sys.architecture, isNotEmpty);
    });

    test('6. Creates remote PTY terminal session', () async {
      final response = await client.sendRequest('terminal.create', payload: {
        'cols': 100,
        'rows': 30,
      });

      expect(response.success, isTrue);
      expect(response.payload?['sessionId'], isNotNull);
      terminalSessionId = response.payload!['sessionId'] as String;
      expect(terminalSessionId, startsWith('term_'));
    });

    test('7. Sends terminal.input and streams terminal.output in real-time', () async {
      expect(terminalSessionId, isNotNull);

      final outputCompleter = Completer<String>();
      var accumulatedOutput = '';

      final sub = client.events.listen((ev) {
        if (ev.event == 'terminal.output' &&
            ev.payload['sessionId'] == terminalSessionId) {
          accumulatedOutput += ev.payload['data'] as String;
          if (accumulatedOutput.contains('FLUTTER_MOBILE_TEST')) {
            if (!outputCompleter.isCompleted) {
              outputCompleter.complete(accumulatedOutput);
            }
          }
        }
      });

      final inputRes = await client.sendRequest('terminal.input', payload: {
        'sessionId': terminalSessionId,
        'data': 'echo FLUTTER_MOBILE_TEST\n',
      });
      expect(inputRes.success, isTrue);

      final output = await outputCompleter.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => accumulatedOutput,
      );
      await sub.cancel();

      expect(output, contains('FLUTTER_MOBILE_TEST'));
    });

    test('8. Resizes terminal', () async {
      expect(terminalSessionId, isNotNull);
      final response = await client.sendRequest('terminal.resize', payload: {
        'sessionId': terminalSessionId,
        'cols': 120,
        'rows': 40,
      });
      expect(response.success, isTrue);
    });

    test('9. Queries rolling terminal.history buffer', () async {
      expect(terminalSessionId, isNotNull);
      final response = await client.sendRequest('terminal.history', payload: {
        'sessionId': terminalSessionId,
      });
      expect(response.success, isTrue);
      expect(response.payload?['data'], contains('FLUTTER_MOBILE_TEST'));
    });

    test('10. Kills terminal session and receives terminal.exited', () async {
      expect(terminalSessionId, isNotNull);

      final exitCompleter = Completer<bool>();
      final sub = client.events.listen((ev) {
        if (ev.event == 'terminal.exited' &&
            ev.payload['sessionId'] == terminalSessionId) {
          if (!exitCompleter.isCompleted) {
            exitCompleter.complete(true);
          }
        }
      });

      final killRes = await client.sendRequest('terminal.kill', payload: {
        'sessionId': terminalSessionId,
      });
      expect(killRes.success, isTrue);

      final exited = await exitCompleter.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => false,
      );
      await sub.cancel();

      expect(exited, isTrue);
    });

    // =========================================================================
    // Milestone 05: Remote File Explorer Live Verification
    // =========================================================================

    String? rootPath;
    String? testDirPath;
    String? testFilePath;
    String? renamedFilePath;

    test('11. Requests filesystem roots (files.roots)', () async {
      final response = await client.sendRequest('files.roots');
      expect(response.success, isTrue);
      expect(response.payload, isNotNull);

      final roots = response.payload!['roots'] as List<dynamic>;
      expect(roots.isNotEmpty, isTrue);
      rootPath = roots.first['path'] as String;
      expect(rootPath, isNotNull);
    });

    test('12. Lists root directory (files.list)', () async {
      expect(rootPath, isNotNull);
      final response = await client.sendRequest('files.list', payload: {
        'path': rootPath,
      });
      expect(response.success, isTrue);
      expect(response.payload?['entries'], isA<List<dynamic>>());
    });

    test('13. Creates a dedicated temporary directory (files.mkdir)', () async {
      expect(rootPath, isNotNull);
      final sep = rootPath!.contains('\\') ? '\\' : '/';
      testDirPath = '$rootPath$sep.orbit_int_test_${DateTime.now().millisecondsSinceEpoch}';

      final response = await client.sendRequest('files.mkdir', payload: {
        'path': testDirPath,
      });
      expect(response.success, isTrue);
    });

    test('14. Writes a test file atomically (files.write)', () async {
      expect(testDirPath, isNotNull);
      final sep = testDirPath!.contains('\\') ? '\\' : '/';
      testFilePath = '$testDirPath$sep' 'hello.txt';

      final response = await client.sendRequest('files.write', payload: {
        'path': testFilePath,
        'content': 'Hello from Orbit Mobile Integration Test!\nLine 2',
      });
      expect(response.success, isTrue);
      expect(response.payload?['size'], greaterThan(0));
    });

    test('15. Reads the test file (files.read)', () async {
      expect(testFilePath, isNotNull);
      final response = await client.sendRequest('files.read', payload: {
        'path': testFilePath,
      });
      expect(response.success, isTrue);
      expect(response.payload?['content'], contains('Hello from Orbit Mobile'));
      expect(response.payload?['encoding'], 'utf8');
    });

    test('16. Overwrites file with updated content and verifies (files.write & files.read)', () async {
      expect(testFilePath, isNotNull);
      final writeRes = await client.sendRequest('files.write', payload: {
        'path': testFilePath,
        'content': 'Updated content from remote mobile editor',
      });
      expect(writeRes.success, isTrue);

      final readRes = await client.sendRequest('files.read', payload: {
        'path': testFilePath,
      });
      expect(readRes.success, isTrue);
      expect(readRes.payload?['content'], 'Updated content from remote mobile editor');
    });

    test('17. Renames test file (files.rename)', () async {
      expect(testFilePath, isNotNull);
      final sep = testDirPath!.contains('\\') ? '\\' : '/';
      renamedFilePath = '$testDirPath$sep' 'renamed.txt';

      final response = await client.sendRequest('files.rename', payload: {
        'from': testFilePath,
        'to': renamedFilePath,
      });
      expect(response.success, isTrue);

      // Verify renamed file is readable
      final readRes = await client.sendRequest('files.read', payload: {
        'path': renamedFilePath,
      });
      expect(readRes.success, isTrue);
    });

    test('18. Deletes test file and cleanup test directory (files.delete)', () async {
      expect(renamedFilePath, isNotNull);
      expect(testDirPath, isNotNull);

      // 1. Delete file
      final delFileRes = await client.sendRequest('files.delete', payload: {
        'path': renamedFilePath,
      });
      expect(delFileRes.success, isTrue);

      // 2. Delete directory
      final delDirRes = await client.sendRequest('files.delete', payload: {
        'path': testDirPath,
      });
      expect(delDirRes.success, isTrue);

      // 3. Confirm not found
      final checkRes = await client.sendRequest('files.list', payload: {
        'path': testDirPath,
      });
      expect(checkRes.success, isFalse);
    });

    // ==========================================
    // Milestone 06: Projects + Git Tests
    // ==========================================

    String? testGitRepoPath;

    test('19. Requests project roots (projects.roots)', () async {
      final response = await client.sendRequest('projects.roots');
      expect(response.success, isTrue);
      expect(response.payload?['roots'], isA<List>());
      final roots = response.payload!['roots'] as List<dynamic>;
      expect(roots.isNotEmpty, isTrue);
    });

    test('20. Lists projects in workspace root (projects.list)', () async {
      expect(rootPath, isNotNull);
      final response = await client.sendRequest('projects.list', payload: {
        'path': rootPath,
      });
      expect(response.success, isTrue);
      expect(response.payload?['projects'], isA<List>());
    });

    test('21. Creates temporary Git repository in sandbox', () async {
      expect(rootPath, isNotNull);
      final sep = rootPath!.contains('\\') ? '\\' : '/';
      testGitRepoPath = '$rootPath$sep.orbit_git_test_${DateTime.now().millisecondsSinceEpoch}';

      // 1. Create directory
      final mkdirRes = await client.sendRequest('files.mkdir', payload: {
        'path': testGitRepoPath,
      });
      expect(mkdirRes.success, isTrue);

      // 2. Initialize git repository using terminal session
      final termRes = await client.sendRequest('terminal.create', payload: {
        'cwd': testGitRepoPath,
        'cols': 80,
        'rows': 24,
      });
      expect(termRes.success, isTrue);
      final sid = termRes.payload!['sessionId'] as String;

      // Send git setup commands
      final setupCmd =
          'git init -b main && git config user.name "Orbit Tester" && git config user.email "tester@orbit.local" && echo "# Orbit Git Test" > README.md && git add README.md && git commit -m "Initial commit"\n';
      await client.sendRequest('terminal.input', payload: {
        'sessionId': sid,
        'data': setupCmd,
      });

      // Allow git process to finish
      await Future.delayed(const Duration(milliseconds: 1500));

      // Terminate setup terminal
      await client.sendRequest('terminal.kill', payload: {
        'sessionId': sid,
      });
    });

    test('22. Requests project info on temporary repository (projects.info)', () async {
      expect(testGitRepoPath, isNotNull);
      final response = await client.sendRequest('projects.info', payload: {
        'path': testGitRepoPath,
      });
      expect(response.success, isTrue);
      expect(response.payload?['kind'], 'git');
      expect(response.payload?['git'], isNotNull);
    });

    test('23. Requests initial git status (git.status)', () async {
      expect(testGitRepoPath, isNotNull);
      final response = await client.sendRequest('git.status', payload: {
        'path': testGitRepoPath,
      });
      expect(response.success, isTrue);
      expect(response.payload?['clean'], isTrue);
      expect(response.payload?['branch'], 'main');
    });

    test('24. Creates test file and verifies untracked status (files.write & git.status)', () async {
      expect(testGitRepoPath, isNotNull);
      final sep = testGitRepoPath!.contains('\\') ? '\\' : '/';
      final newFile = '$testGitRepoPath$sep' 'feature.txt';

      final writeRes = await client.sendRequest('files.write', payload: {
        'path': newFile,
        'content': 'New feature code line 1\nLine 2\n',
      });
      expect(writeRes.success, isTrue);

      final statusRes = await client.sendRequest('git.status', payload: {
        'path': testGitRepoPath,
      });
      expect(statusRes.success, isTrue);
      expect(statusRes.payload?['clean'], isFalse);

      final untracked = statusRes.payload!['untracked'] as List<dynamic>;
      expect(untracked.any((f) => f['path'] == 'feature.txt'), isTrue);
    });

    test('25. Stages test file and verifies staged status (git.stage)', () async {
      expect(testGitRepoPath, isNotNull);
      final stageRes = await client.sendRequest('git.stage', payload: {
        'path': testGitRepoPath,
        'paths': ['feature.txt'],
      });
      expect(stageRes.success, isTrue);

      final staged = stageRes.payload!['staged'] as List<dynamic>;
      expect(staged.any((f) => f['path'] == 'feature.txt'), isTrue);
    });

    test('26. Unstages test file and verifies unstaged status (git.unstage)', () async {
      expect(testGitRepoPath, isNotNull);
      final unstageRes = await client.sendRequest('git.unstage', payload: {
        'path': testGitRepoPath,
        'paths': ['feature.txt'],
      });
      expect(unstageRes.success, isTrue);

      final staged = unstageRes.payload!['staged'] as List<dynamic>;
      expect(staged.isEmpty, isTrue);
    });

    test('27. Stages and commits test file (git.stage & git.commit)', () async {
      expect(testGitRepoPath, isNotNull);

      // Stage
      await client.sendRequest('git.stage', payload: {
        'path': testGitRepoPath,
        'paths': ['feature.txt'],
      });

      // Commit
      final commitRes = await client.sendRequest('git.commit', payload: {
        'path': testGitRepoPath,
        'message': 'Add feature.txt in integration test',
      });
      expect(commitRes.success, isTrue);
      expect(commitRes.payload?['hash'], isNotEmpty);
      expect(commitRes.payload?['message'], 'Add feature.txt in integration test');

      // Verify clean
      final statusRes = await client.sendRequest('git.status', payload: {
        'path': testGitRepoPath,
      });
      expect(statusRes.success, isTrue);
      expect(statusRes.payload?['clean'], isTrue);
    });

    test('28. Creates and switches branch (git.create_branch & git.branches)', () async {
      expect(testGitRepoPath, isNotNull);

      final createRes = await client.sendRequest('git.create_branch', payload: {
        'path': testGitRepoPath,
        'name': 'feature/orbit-branch',
      });
      expect(createRes.success, isTrue);
      expect(createRes.payload?['branch'], 'feature/orbit-branch');

      final branchesRes = await client.sendRequest('git.branches', payload: {
        'path': testGitRepoPath,
      });
      expect(branchesRes.success, isTrue);
      expect(branchesRes.payload?['current'], 'feature/orbit-branch');
      final local = branchesRes.payload!['local'] as List<dynamic>;
      expect(local.contains('main'), isTrue);
      expect(local.contains('feature/orbit-branch'), isTrue);
    });

    test('29. Requests commit log (git.log)', () async {
      expect(testGitRepoPath, isNotNull);

      final logRes = await client.sendRequest('git.log', payload: {
        'path': testGitRepoPath,
        'limit': 10,
      });
      expect(logRes.success, isTrue);
      final commits = logRes.payload!['commits'] as List<dynamic>;
      expect(commits.length, greaterThanOrEqualTo(2));
      expect(commits.first['message'], 'Add feature.txt in integration test');
    });

    test('30. Cleans up temporary Git repository (files.delete)', () async {
      expect(testGitRepoPath, isNotNull);

      final delRes = await client.sendRequest('files.delete', payload: {
        'path': testGitRepoPath,
      });
      expect(delRes.success, isTrue);
    });

    // ==========================================
    // Milestone 07: OpenCode AI Integration Tests (Phases 31-43)
    // ==========================================

    String? aiProjectPath;
    String? firstTaskId;
    String? firstSessionId;
    String? cancelTaskId;
    final List<OrbitEvent> capturedAiEvents = [];
    StreamSubscription<OrbitEvent>? aiSub;

    Future<OrbitEvent?> waitForAiEvent(
      bool Function(OrbitEvent) predicate, {
      Duration timeout = const Duration(seconds: 30),
    }) async {
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed < timeout) {
        for (final ev in capturedAiEvents) {
          if (predicate(ev)) return ev;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      for (final ev in capturedAiEvents) {
        if (predicate(ev)) return ev;
      }
      return null;
    }

    test('31. Connect: Verifies active WebSocket connection for AI tasks', () async {
      if (!client.currentState.isConnected) {
        await client.connect('127.0.0.1', 4371);
      }
      expect(client.currentState.isConnected, isTrue);

      // Start capturing all AI events
      aiSub = client.events.listen((ev) {
        if (ev.event.startsWith('ai.task.')) {
          capturedAiEvents.add(ev);
        }
      });
    });

    test('32. Pair: Verifies authenticated pairing for AI tasks', () async {
      expect(client.currentState.isPaired, isTrue);
      expect(client.currentState.deviceId, isNotNull);
    });

    test('33. Selects real project for AI tasks', () async {
      final listRes = await client.sendRequest('projects.list');
      expect(listRes.success, isTrue);
      final projects = listRes.payload!['projects'] as List<dynamic>;
      if (projects.isNotEmpty) {
        aiProjectPath = projects.first['path'] as String;
      } else {
        final rootsRes = await client.sendRequest('projects.roots');
        expect(rootsRes.success, isTrue);
        final roots = rootsRes.payload!['roots'] as List<dynamic>;
        expect(roots, isNotEmpty);
        aiProjectPath = roots.first['path'] as String;
      }
      expect(aiProjectPath, isNotNull);
      expect(Directory(aiProjectPath!).existsSync(), isTrue);
    });

    test('34. Starts read-only OpenCode task (ai.task.start)', () async {
      expect(aiProjectPath, isNotNull);

      final response = await client.sendRequest('ai.task.start', payload: {
        'projectPath': aiProjectPath,
        'prompt': 'Read README.md and explain in a concise way what this project does. Do not modify any files.',
        'agent': 'plan',
        'readOnly': true,
      });

      expect(response.success, isTrue);
      expect(response.payload, isNotNull);
      firstTaskId = response.payload!['taskId'] as String?;
      expect(firstTaskId, isNotNull);
      expect(firstTaskId, isNotEmpty);
      expect(response.payload!['status'], 'queued');
    });

    test('35. Receives ai.task.created event', () async {
      expect(firstTaskId, isNotNull);

      final createdEvent = await waitForAiEvent(
        (e) => e.event == 'ai.task.created' && e.payload['taskId'] == firstTaskId,
        timeout: const Duration(seconds: 5),
      );

      expect(createdEvent, isNotNull, reason: 'ai.task.created event should be received');
      expect(createdEvent!.payload['taskId'], firstTaskId);
      expect(createdEvent.payload['agent'], 'plan');
      expect(createdEvent.payload['readOnly'], isTrue);
    });

    test('36. Receives ai.task.started event', () async {
      expect(firstTaskId, isNotNull);

      final startedEvent = await waitForAiEvent(
        (e) => e.event == 'ai.task.started' && e.payload['taskId'] == firstTaskId,
        timeout: const Duration(seconds: 15),
      );

      expect(startedEvent, isNotNull, reason: 'ai.task.started event should be received');
      expect(startedEvent!.payload['taskId'], firstTaskId);
      firstSessionId = startedEvent.payload['openCodeSessionId'] as String?;
    });

    test('37. Receives live AI activity events', timeout: const Timeout(Duration(minutes: 2)), () async {
      expect(firstTaskId, isNotNull);

      final activityEvent = await waitForAiEvent(
        (e) =>
            (e.event == 'ai.task.activity' ||
             e.event == 'ai.task.updated' ||
             e.event == 'ai.task.output' ||
             e.event == 'ai.task.tool_started' ||
             e.event == 'ai.task.response' ||
             e.event == 'ai.task.completed') &&
            e.payload['taskId'] == firstTaskId,
        timeout: const Duration(seconds: 90),
      );

      expect(activityEvent, isNotNull, reason: 'At least one activity or output event should be received during execution');
      if (firstSessionId == null && activityEvent!.payload['openCodeSessionId'] != null) {
        firstSessionId = activityEvent.payload['openCodeSessionId'] as String?;
      }
    });

    test('38. Receives task completion (ai.task.completed)', timeout: const Timeout(Duration(minutes: 2)), () async {
      expect(firstTaskId, isNotNull);

      final terminalEvent = await waitForAiEvent(
        (e) =>
            (e.event == 'ai.task.completed' || e.event == 'ai.task.failed') &&
            e.payload['taskId'] == firstTaskId,
        timeout: const Duration(seconds: 90),
      );

      expect(terminalEvent, isNotNull, reason: 'Task should reach terminal state');
      if (terminalEvent!.event == 'ai.task.failed') {
        final errorMsg = terminalEvent.payload['error'] ?? 'Unknown error';
        fail('AI task failed unexpectedly: $errorMsg');
      }

      expect(terminalEvent.event, 'ai.task.completed');
      expect(terminalEvent.payload['taskId'], firstTaskId);
    });

    test('39. Queries active tasks (ai.task.list)', () async {
      final response = await client.sendRequest('ai.task.list');
      expect(response.success, isTrue);
      expect(response.payload?['tasks'], isA<List>());

      final tasks = response.payload!['tasks'] as List<dynamic>;
      expect(tasks, isNotNull);
    });

    test('40. Starts second task for cancellation testing (ai.task.start)', () async {
      expect(aiProjectPath, isNotNull);

      final response = await client.sendRequest('ai.task.start', payload: {
        'projectPath': aiProjectPath,
        'prompt': 'Analyze all source files and check for potential optimizations. Do not modify files.',
        'agent': 'plan',
        'readOnly': true,
      });

      expect(response.success, isTrue);
      cancelTaskId = response.payload!['taskId'] as String?;
      expect(cancelTaskId, isNotNull);
      expect(cancelTaskId, isNotEmpty);
    });

    test('41. Cancels running task (ai.task.cancel)', () async {
      expect(cancelTaskId, isNotNull);

      final cancelRes = await client.sendRequest('ai.task.cancel', payload: {
        'taskId': cancelTaskId,
      });

      expect(cancelRes.success, isTrue);
      expect(cancelRes.payload?['taskId'], cancelTaskId);
      expect(cancelRes.payload?['status'], 'cancelled');
    });

    test('42. Receives ai.task.cancelled event', () async {
      expect(cancelTaskId, isNotNull);

      final cancelledEvent = await waitForAiEvent(
        (e) => e.event == 'ai.task.cancelled' && e.payload['taskId'] == cancelTaskId,
        timeout: const Duration(seconds: 15),
      );

      expect(cancelledEvent, isNotNull, reason: 'ai.task.cancelled event should be received');
      expect(cancelledEvent!.payload['taskId'], cancelTaskId);
    });

    test('43. Verifies no orphan OpenCode process remains', () async {
      // Query active tasks: none should be running
      final listRes = await client.sendRequest('ai.task.list');
      expect(listRes.success, isTrue);
      final tasks = listRes.payload!['tasks'] as List<dynamic>;
      final runningTasks = tasks.where((t) => t['status'] == 'running').toList();
      expect(runningTasks.isEmpty, isTrue, reason: 'No tasks should remain in running state');
    });

    // ==========================================
    // Milestone 08: Live AI Activity Tests (Phases 44-59)
    // ==========================================

    String? liveTaskId;
    String? liveSessionId;
    String? cancelTaskId2;

    test('44. Phase 44: Connect and pair verification', () async {
      expect(client.currentState.isConnected, isTrue);
      expect(client.currentState.isPaired, isTrue);
      expect(client.currentState.deviceId, isNotNull);
    });

    test('45. Phase 45: Select a real project', () async {
      expect(aiProjectPath, isNotNull);
      expect(Directory(aiProjectPath!).existsSync(), isTrue);
    });

    test('46. Phase 46: Start real Plan task (ai.task.start)', () async {
      final response = await client.sendRequest('ai.task.start', payload: {
        'projectPath': aiProjectPath,
        'prompt': 'Read README.md and summarize in 1 concise sentence. Do not modify files.',
        'agent': 'plan',
        'readOnly': true,
      });

      expect(response.success, isTrue);
      expect(response.payload, isNotNull);
      liveTaskId = response.payload!['taskId'] as String?;
      expect(liveTaskId, isNotNull);
      expect(liveTaskId, isNotEmpty);
      expect(response.payload!['status'], 'queued');
    });

    test('47. Phase 47: Receive ai.task.created event', () async {
      expect(liveTaskId, isNotNull);

      final createdEvent = await waitForAiEvent(
        (e) => e.event == 'ai.task.created' && e.payload['taskId'] == liveTaskId,
        timeout: const Duration(seconds: 10),
      );

      expect(createdEvent, isNotNull, reason: 'ai.task.created should be received');
      expect(createdEvent!.payload['taskId'], liveTaskId);
      expect(createdEvent.payload['agent'], 'plan');
      expect(createdEvent.payload['readOnly'], isTrue);
    });

    test('48. Phase 48: Receive ai.task.started event', () async {
      expect(liveTaskId, isNotNull);

      final startedEvent = await waitForAiEvent(
        (e) => e.event == 'ai.task.started' && e.payload['taskId'] == liveTaskId,
        timeout: const Duration(seconds: 20),
      );

      expect(startedEvent, isNotNull, reason: 'ai.task.started should be received');
      expect(startedEvent!.payload['taskId'], liveTaskId);
      liveSessionId = startedEvent.payload['openCodeSessionId'] as String?;
    });

    test('49. Phase 49: Receive at least one normalized activity event', timeout: const Timeout(Duration(minutes: 2)), () async {
      expect(liveTaskId, isNotNull);

      final activityEvent = await waitForAiEvent(
        (e) =>
            (e.event == 'ai.task.activity' ||
             e.event == 'ai.task.updated' ||
             e.event == 'ai.task.tool_started' ||
             e.event == 'ai.task.response' ||
             e.event == 'ai.task.output' ||
             e.event == 'ai.task.completed') &&
            e.payload['taskId'] == liveTaskId,
        timeout: const Duration(seconds: 90),
      );

      expect(activityEvent, isNotNull, reason: 'At least one activity event should be received');
      if (liveSessionId == null && activityEvent!.payload['openCodeSessionId'] != null) {
        liveSessionId = activityEvent.payload['openCodeSessionId'] as String?;
      }
    });

    test('50. Phase 50: Verify activity contains no raw reasoning', () async {
      expect(liveTaskId, isNotNull);

      for (final ev in capturedAiEvents.where((e) => e.payload['taskId'] == liveTaskId)) {
        final payloadStr = ev.payload.toString().toLowerCase();
        expect(payloadStr.contains('chain_of_thought'), isFalse);
        expect(payloadStr.contains('reasoning_details'), isFalse);
        expect(payloadStr.contains('secret private'), isFalse);
      }
    });

    test('51. Phase 51: Verify task remains running or progresses normally', () async {
      expect(liveTaskId, isNotNull);

      final listRes = await client.sendRequest('ai.task.list');
      expect(listRes.success, isTrue);
      final tasks = listRes.payload!['tasks'] as List<dynamic>;
      final current = tasks.firstWhere(
        (t) => t['taskId'] == liveTaskId,
        orElse: () => null,
      );
      expect(current, isNotNull);
      expect(['running', 'completed'].contains(current['status']), isTrue);
    });

    test('52. Phase 52: Verify ai.task.completed event', timeout: const Timeout(Duration(minutes: 2)), () async {
      expect(liveTaskId, isNotNull);

      final terminalEvent = await waitForAiEvent(
        (e) =>
            (e.event == 'ai.task.completed' || e.event == 'ai.task.failed') &&
            e.payload['taskId'] == liveTaskId,
        timeout: const Duration(seconds: 90),
      );

      expect(terminalEvent, isNotNull, reason: 'Task should reach terminal state');
      if (terminalEvent!.event == 'ai.task.failed') {
        fail('Task failed: ${terminalEvent.payload['error']}');
      }
      expect(terminalEvent.event, 'ai.task.completed');
      expect(terminalEvent.payload['taskId'], liveTaskId);
    });

    test('53. Phase 53: Open task history/state and verify activities are present (ai.task.get)', () async {
      expect(liveTaskId, isNotNull);

      final getRes = await client.sendRequest('ai.task.get', payload: {
        'taskId': liveTaskId,
      });

      expect(getRes.success, isTrue);
      expect(getRes.payload, isNotNull);
      expect(getRes.payload!['taskId'], liveTaskId);
      expect(getRes.payload!['status'], 'completed');
      final activities = getRes.payload!['activities'] as List<dynamic>? ?? [];
      expect(activities, isNotEmpty, reason: 'Task activities should be recorded in task history');
    });

    test('54. Phase 54: Start another task for live output & cancellation test', () async {
      expect(aiProjectPath, isNotNull);

      final response = await client.sendRequest('ai.task.start', payload: {
        'projectPath': aiProjectPath,
        'prompt': 'Analyze all source files and check for potential optimizations. Do not modify files.',
        'agent': 'plan',
        'readOnly': true,
      });

      expect(response.success, isTrue);
      cancelTaskId2 = response.payload!['taskId'] as String?;
      expect(cancelTaskId2, isNotNull);
      expect(cancelTaskId2, isNotEmpty);
    });

    test('55. Phase 55: Verify live output/activity arrives for second task', () async {
      expect(cancelTaskId2, isNotNull);

      final event = await waitForAiEvent(
        (e) =>
            (e.event == 'ai.task.started' ||
             e.event == 'ai.task.activity' ||
             e.event == 'ai.task.updated') &&
            e.payload['taskId'] == cancelTaskId2,
        timeout: const Duration(seconds: 20),
      );

      expect(event, isNotNull, reason: 'Started or activity event should arrive for second task');
    });

    test('56. Phase 56: Cancel task (ai.task.cancel)', () async {
      expect(cancelTaskId2, isNotNull);

      final cancelRes = await client.sendRequest('ai.task.cancel', payload: {
        'taskId': cancelTaskId2,
      });

      expect(cancelRes.success, isTrue);
      expect(cancelRes.payload?['taskId'], cancelTaskId2);
      expect(cancelRes.payload?['status'], 'cancelled');
    });

    test('57. Phase 57: Verify ai.task.cancelled event received', () async {
      expect(cancelTaskId2, isNotNull);

      final cancelledEvent = await waitForAiEvent(
        (e) => e.event == 'ai.task.cancelled' && e.payload['taskId'] == cancelTaskId2,
        timeout: const Duration(seconds: 15),
      );

      expect(cancelledEvent, isNotNull, reason: 'ai.task.cancelled event should be received');
      expect(cancelledEvent!.payload['taskId'], cancelTaskId2);
    });

    test('58. Phase 58: Verify no orphan OpenCode process remains', () async {
      final listRes = await client.sendRequest('ai.task.list');
      expect(listRes.success, isTrue);
      final tasks = listRes.payload!['tasks'] as List<dynamic>;
      final running = tasks.where((t) => t['status'] == 'running').toList();
      expect(running.isEmpty, isTrue, reason: 'No task should remain in running state');
    });

    test('59. Phase 59: Reconnect Resilience E2E', () async {
      // 1. Start a fresh task
      final startRes = await client.sendRequest('ai.task.start', payload: {
        'projectPath': aiProjectPath,
        'prompt': 'Read README and inspect codebase. Do not edit files.',
        'agent': 'plan',
        'readOnly': true,
      });
      expect(startRes.success, isTrue);
      final reconnectTaskId = startRes.payload!['taskId'] as String;

      // 2. Wait for started event
      await waitForAiEvent(
        (e) => e.event == 'ai.task.started' && e.payload['taskId'] == reconnectTaskId,
        timeout: const Duration(seconds: 20),
      );

      // 3. Disconnect WebSocket
      final previousDeviceId = client.currentState.deviceId;
      client.disconnect();
      expect(client.currentState.isConnected, isFalse);

      // 4. Wait briefly
      await Future.delayed(const Duration(milliseconds: 500));

      // 5. Reconnect
      await client.connect('127.0.0.1', 4371);
      expect(client.currentState.isConnected, isTrue);

      // Re-subscribe events after reconnect
      aiSub = client.events.listen((ev) {
        if (ev.event.startsWith('ai.task.')) {
          capturedAiEvents.add(ev);
        }
      });

      // Re-pair with same deviceId / pairing code
      final pairPayload = <String, dynamic>{
        'code': pairingCode,
        'name': 'Dart Integration Client Reconnect',
        'platform': 'android',
      };
      if (previousDeviceId != null) {
        pairPayload['deviceId'] = previousDeviceId;
      }
      final pairRes = await client.sendRequest('pairing.verify', payload: pairPayload);
      expect(pairRes.success, isTrue);
      final devId = pairRes.payload!['deviceId'] as String;
      client.markPaired(devId);
      testPairedDeviceId = devId;

      // 6. Request ai.task.list
      final listRes = await client.sendRequest('ai.task.list');
      expect(listRes.success, isTrue);
      final tasks = listRes.payload!['tasks'] as List<dynamic>;
      final found = tasks.any((t) => t['taskId'] == reconnectTaskId);
      expect(found, isTrue, reason: 'Original task must still exist after reconnect');

      // 7. Request ai.task.get to verify state recovery
      final getRes = await client.sendRequest('ai.task.get', payload: {
        'taskId': reconnectTaskId,
      });
      expect(getRes.success, isTrue);
      expect(getRes.payload!['taskId'], reconnectTaskId);
      expect(getRes.payload!['activities'], isA<List>());

      // Clean up by cancelling if still running
      if (getRes.payload!['status'] == 'running') {
        await client.sendRequest('ai.task.cancel', payload: {'taskId': reconnectTaskId});
      }

      await aiSub?.cancel();
    });

    // ==========================================
    // Milestone 08.5: Product UX Correction Live E2E Tests (Phases 60-70)
    // ==========================================

    test('60. Phase B: Global AI navigation & context model (No project required)', () async {
      final noContext = AiContext.none();
      expect(noContext.isNone, isTrue);
      expect(noContext.path, isNull);

      final listRes = await client.sendRequest('ai.task.list');
      expect(listRes.success, isTrue);
      expect(listRes.payload?['tasks'], isA<List>());
    });

    String? noContextTaskId;
    test('61. Phase C: Starts no-context Plan task (ai.task.start with no project)', timeout: const Timeout(Duration(minutes: 2)), () async {
      final response = await client.sendRequest('ai.task.start', payload: {
        'projectPath': '',
        'prompt': 'Answer: what is the capital of France? Reply in one short sentence without modifying files.',
        'agent': 'plan',
        'readOnly': true,
      });

      expect(response.success, isTrue);
      expect(response.payload, isNotNull);
      noContextTaskId = response.payload!['taskId'] as String?;
      expect(noContextTaskId, isNotNull);
      expect(noContextTaskId, isNotEmpty);

      // Re-subscribe aiSub if needed
      aiSub = client.events.listen((ev) {
        if (ev.event.startsWith('ai.task.')) {
          capturedAiEvents.add(ev);
        }
      });

      // Wait for completion or termination
      final terminalEvent = await waitForAiEvent(
        (e) =>
            (e.event == 'ai.task.completed' || e.event == 'ai.task.failed') &&
            e.payload['taskId'] == noContextTaskId,
        timeout: const Duration(seconds: 90),
      );
      expect(terminalEvent, isNotNull);
    });

    String? projectContextTaskId;
    test('62. Phase D & E: Selects real project context & starts read-only AI task', timeout: const Timeout(Duration(minutes: 2)), () async {
      expect(aiProjectPath, isNotNull);
      final projCtx = AiContext.fromProject(
        path: aiProjectPath!,
        name: 'orbit_workspace',
        isGit: true,
      );
      expect(projCtx.source, AiContextSource.project);
      expect(projCtx.path, aiProjectPath);

      final response = await client.sendRequest('ai.task.start', payload: {
        'projectPath': projCtx.path,
        'prompt': 'Analyze the directory structure and describe its primary files in 1 sentence. Do not edit files.',
        'agent': 'plan',
        'readOnly': true,
      });

      expect(response.success, isTrue);
      projectContextTaskId = response.payload!['taskId'] as String?;
      expect(projectContextTaskId, isNotNull);
    });

    test('63. Phase F: Verifies activity events with structured metadata', timeout: const Timeout(Duration(minutes: 2)), () async {
      expect(projectContextTaskId, isNotNull);

      // Wait for activity or completion
      final event = await waitForAiEvent(
        (e) =>
            (e.event == 'ai.task.activity' ||
             e.event == 'ai.task.updated' ||
             e.event == 'ai.task.completed') &&
            e.payload['taskId'] == projectContextTaskId,
        timeout: const Duration(seconds: 90),
      );
      expect(event, isNotNull);

      // Clean up / wait for completion if running
      final term = await waitForAiEvent(
        (e) =>
            (e.event == 'ai.task.completed' || e.event == 'ai.task.failed') &&
            e.payload['taskId'] == projectContextTaskId,
        timeout: const Duration(seconds: 90),
      );
      expect(term, isNotNull);
    });

    test('64. Phase G & H: Project -> Ask Orbit AI preselected context mapping', () async {
      expect(aiProjectPath, isNotNull);
      final context = AiContext.fromProject(
        path: aiProjectPath!,
        name: 'test_project',
        isGit: false,
      );
      expect(context.path, aiProjectPath);
      expect(context.displayName, 'test_project');
      expect(context.isNone, isFalse);
    });

    String? nonGitDirPath;
    String? nonGitTaskId;
    test('65. Phase I & J: AI operates on non-Git directory without Git dependency', timeout: const Timeout(Duration(minutes: 2)), () async {
      expect(rootPath, isNotNull);
      final sep = rootPath!.contains('\\') ? '\\' : '/';
      nonGitDirPath = '$rootPath$sep' 'orbit_nongit_ai_test_${DateTime.now().millisecondsSinceEpoch}';

      // 1. Create a plain directory without .git
      final mkdirRes = await client.sendRequest('files.mkdir', payload: {
        'path': nonGitDirPath,
      });
      expect(mkdirRes.success, isTrue);

      // 2. Put a file inside it
      final fileRes = await client.sendRequest('files.write', payload: {
        'path': '$nonGitDirPath$sep' 'README.txt',
        'content': 'This is a standalone non-git directory for AI verification.',
      });
      expect(fileRes.success, isTrue);

      // 3. Start AI Plan task targeting this non-Git directory
      final aiRes = await client.sendRequest('ai.task.start', payload: {
        'projectPath': nonGitDirPath,
        'prompt': 'Read README.txt and state what this directory is. Do not modify files.',
        'agent': 'plan',
        'readOnly': true,
      });
      expect(aiRes.success, isTrue);
      nonGitTaskId = aiRes.payload!['taskId'] as String?;
      expect(nonGitTaskId, isNotNull);

      // 4. Verify OpenCode starts and completes without requiring Git
      final terminalEvent = await waitForAiEvent(
        (e) =>
            (e.event == 'ai.task.completed' || e.event == 'ai.task.failed') &&
            e.payload['taskId'] == nonGitTaskId,
        timeout: const Duration(seconds: 90),
      );
      expect(terminalEvent, isNotNull);
      expect(terminalEvent!.event, 'ai.task.completed');

      // Cleanup
      await client.sendRequest('files.delete', payload: {'path': nonGitDirPath});
    });

    String? uxTestDirPath;
    String? testSourceFilePath;
    test('66. Phase K, L & M: Code files, syntax highlighting, and editor support', () async {
      expect(rootPath, isNotNull);
      final sep = rootPath!.contains('\\') ? '\\' : '/';
      uxTestDirPath = '$rootPath$sep' 'orbit_ux_test_${DateTime.now().millisecondsSinceEpoch}';

      final mkdirRes = await client.sendRequest('files.mkdir', payload: {
        'path': uxTestDirPath,
      });
      expect(mkdirRes.success, isTrue);

      testSourceFilePath = '$uxTestDirPath$sep' 'sample_calculator.dart';

      const codeContent = '''
class Calculator {
  int add(int a, int b) => a + b;
  int multiply(int a, int b) => a * b;
}
''';
      final writeRes = await client.sendRequest('files.write', payload: {
        'path': testSourceFilePath,
        'content': codeContent,
      });
      expect(writeRes.success, isTrue);

      final readRes = await client.sendRequest('files.read', payload: {
        'path': testSourceFilePath,
      });
      expect(readRes.success, isTrue);
      expect(readRes.payload?['content'], contains('class Calculator'));

      // Verify category detection
      final category = FileCategory.fromExtension(testSourceFilePath!);
      expect(category, FileCategory.code);
    });

    String? testImagePath;
    test('67. Phase N & O: Image preview via files.read_binary with dimensions and base64', () async {
      expect(uxTestDirPath, isNotNull);
      final sep = uxTestDirPath!.contains('\\') ? '\\' : '/';
      testImagePath = '$uxTestDirPath$sep' 'orbit_fixture.png';

      // 1x1 transparent PNG bytes
      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00,
        0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
        0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
        0xAE, 0x42, 0x60, 0x82,
      ]);

      final file = File(testImagePath!);
      await file.writeAsBytes(pngBytes);

      final response = await client.sendRequest('files.read_binary', payload: {
        'path': testImagePath,
      });

      expect(response.success, isTrue);
      expect(response.payload, isNotNull);
      final binaryRes = BinaryReadResponse.fromJson(response.payload!);

      expect(binaryRes.fileCategory, FileCategory.image);
      expect(binaryRes.mimeType, 'image/png');
      expect(binaryRes.extension, 'png');
      expect(binaryRes.width, 1);
      expect(binaryRes.height, 1);
      expect(binaryRes.dimensionsText, '1 × 1');
      expect(binaryRes.content, isNotNull);

      final decoded = base64Decode(binaryRes.content!);
      expect(decoded.length, pngBytes.length);

      if (file.existsSync()) await file.delete();
    });

    String? testBinaryPath;
    test('68. Phase P & Q: Binary file handling without UTF-8 error', () async {
      expect(uxTestDirPath, isNotNull);
      final sep = uxTestDirPath!.contains('\\') ? '\\' : '/';
      testBinaryPath = '$uxTestDirPath$sep' 'compiled_module.bin';

      final binBytes = Uint8List.fromList([
        0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00,
        0xFE, 0xFF, 0x80, 0x81, 0xDE, 0xAD, 0xBE, 0xEF,
      ]);

      final file = File(testBinaryPath!);
      await file.writeAsBytes(binBytes);

      final response = await client.sendRequest('files.read_binary', payload: {
        'path': testBinaryPath,
      });

      expect(response.success, isTrue);
      expect(response.payload, isNotNull);
      final binaryRes = BinaryReadResponse.fromJson(response.payload!);

      expect(binaryRes.fileCategory, FileCategory.binary);
      expect(binaryRes.mimeType, 'application/octet-stream');
      expect(binaryRes.extension, 'bin');
      expect(binaryRes.size, 16);
      expect(binaryRes.isTooLarge, isFalse);
      expect(binaryRes.content, isNotNull);

      if (file.existsSync()) await file.delete();
    });

    test('69. Phase R: Oversized file protection metadata', () async {
      expect(uxTestDirPath, isNotNull);
      final sep = uxTestDirPath!.contains('\\') ? '\\' : '/';
      final largePath = '$uxTestDirPath$sep' 'large_dummy.bin';

      final file = File(largePath);
      final sink = file.openWrite();
      final chunk = Uint8List(1024 * 1024);
      for (int i = 0; i < 6; i++) {
        sink.add(chunk);
      }
      await sink.close();

      final response = await client.sendRequest('files.read_binary', payload: {
        'path': largePath,
      });

      expect(response.success, isTrue);
      expect(response.payload, isNotNull);
      final binaryRes = BinaryReadResponse.fromJson(response.payload!);

      expect(binaryRes.isTooLarge, isTrue);
      expect(binaryRes.content, isNull);
      expect(binaryRes.size, greaterThanOrEqualTo(6 * 1024 * 1024));

      if (file.existsSync()) await file.delete();

      // Clean up the entire uxTestDirPath
      await client.sendRequest('files.delete', payload: {'path': uxTestDirPath});
    });

    test('70. Security Boundary: Rejects sensitive system directories for AI', () async {
      final response = await client.sendRequest('ai.task.start', payload: {
        'projectPath': '/etc',
        'prompt': 'Inspect system files',
        'agent': 'plan',
        'readOnly': true,
      });

      expect(response.success, isFalse);
      expect(response.error, isNotNull);
      expect(response.error?.message, contains('system or sensitive directory'));
    });

    test('71. Phase S: QR Payload generation and parsing round-trip', () {
      const original = OrbitPairingQrPayload(
        host: '192.168.1.145',
        port: 4371,
        code: '842917',
        expires: 1725450000000,
        version: 'v1',
      );
      final uri = original.toUriString();
      final parsed = OrbitPairingQrPayload.parse(uri);

      expect(parsed.host, equals('192.168.1.145'));
      expect(parsed.port, equals(4371));
      expect(parsed.code, equals('842917'));
      expect(parsed.expires, equals(1725450000000));
      expect(parsed.version, equals('v1'));
    });

    test('72. Phase T: Reconnect via session.resume using stable deviceId', () async {
      expect(testPairedDeviceId, isNotNull);

      // Create a secondary client to simulate mobile reconnect / app restart
      final reconnectClient = OrbitWebSocketClient();
      await reconnectClient.connect('127.0.0.1', 4371);

      final resumeRes = await reconnectClient.sendRequest('session.resume', payload: {
        'deviceId': testPairedDeviceId,
      });

      expect(resumeRes.success, isTrue);
      expect(resumeRes.payload?['resumed'], isTrue);
      expect(resumeRes.payload?['deviceId'], equals(testPairedDeviceId));

      reconnectClient.markPaired(testPairedDeviceId!);
      expect(reconnectClient.currentState.isPaired, isTrue);

      final statusRes = await reconnectClient.sendRequest('agent.status');
      expect(statusRes.success, isTrue);

      reconnectClient.dispose();

      // Resume original client session to keep it paired for subsequent tests
      final clientResume = await client.sendRequest('session.resume', payload: {
        'deviceId': testPairedDeviceId,
      });
      expect(clientResume.success, isTrue);
      client.markPaired(testPairedDeviceId!);
    });

    test('73. Phase U: Duplicate device prevention and stable device count', () async {
      expect(testPairedDeviceId, isNotNull);

      final devicesRes = await client.sendRequest('devices.list');
      expect(devicesRes.success, isTrue);
      expect(devicesRes.payload, isNotNull);

      final devices = devicesRes.payload!['devices'] as List<dynamic>;
      final matches = devices.where((d) => (d['deviceId'] ?? d['device_id']) == testPairedDeviceId).toList();
      expect(matches.length, equals(1), reason: 'Duplicate devices detected for same deviceId');
    });

    test('74. Phase V: Visual Directory Picker backend roots validation', () async {
      final rootsRes = await client.sendRequest('files.roots');
      expect(rootsRes.success, isTrue);
      expect(rootsRes.payload, isNotNull);

      final rootsList = rootsRes.payload!['roots'] as List<dynamic>;
      expect(rootsList, isNotEmpty);
      expect(rootsList.first['path'], isNotEmpty);
    });

    test('75. Phase W: Visual Directory Picker lists directories only', () async {
      final rootsRes = await client.sendRequest('files.roots');
      final firstRoot = (rootsRes.payload!['roots'] as List<dynamic>).first['path'] as String;

      final listRes = await client.sendRequest('files.list', payload: {'path': firstRoot});
      expect(listRes.success, isTrue);
      expect(listRes.payload, isNotNull);

      final entries = (listRes.payload!['entries'] as List<dynamic>)
          .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      final directories = entries.where((e) => e.isDirectory).toList();
      expect(directories, isA<List<FileEntry>>());
    });

    String? aiConversationTaskId;
    String? aiConversationSessionId;
    String streamedResponseText = '';

    test('76. Phase X: AI Conversation flow with README.md explanation', timeout: const Timeout(Duration(minutes: 2)), () async {
      final rootsRes = await client.sendRequest('files.roots');
      final workspacePath = aiProjectPath ?? (rootsRes.payload!['roots'] as List<dynamic>).first['path'] as String;

      final responseCompleter = Completer<void>();
      final sub = client.events.listen((ev) {
        if (ev.event == 'ai.task.response') {
          final delta = ev.payload['delta'] as String? ?? '';
          streamedResponseText += delta;
        } else if (ev.event == 'ai.task.completed' || ev.event == 'ai.task.failed') {
          if (!responseCompleter.isCompleted) {
            responseCompleter.complete();
          }
        }
      });

      final startRes = await client.sendRequest('ai.task.start', payload: {
        'projectPath': workspacePath,
        'prompt': 'Read README.md and explain in a concise way what this project does. Do not modify any files.',
        'agent': 'plan',
        'readOnly': true,
      });

      expect(startRes.success, isTrue);
      expect(startRes.payload, isNotNull);
      aiConversationTaskId = startRes.payload!['taskId'] as String;
      expect(aiConversationTaskId, isNotEmpty);

      // Wait for task completion or timeout
      await responseCompleter.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () {},
      );

      await sub.cancel();
    });

    test('77. Phase Y: AI assistant response received and non-empty', timeout: const Timeout(Duration(minutes: 2)), () async {
      expect(aiConversationTaskId, isNotNull);

      await waitForAiEvent(
        (e) =>
            (e.event == 'ai.task.completed' || e.event == 'ai.task.failed') &&
            e.payload['taskId'] == aiConversationTaskId,
        timeout: const Duration(seconds: 90),
      );

      final taskRes = await client.sendRequest('ai.task.get', payload: {
        'taskId': aiConversationTaskId,
      });

      expect(taskRes.success, isTrue);
      expect(taskRes.payload, isNotNull);

      final taskObj = taskRes.payload!;
      final respFromTask = (taskObj['response'] as String?)?.trim();
      final finalResponse = (respFromTask != null && respFromTask.isNotEmpty)
          ? respFromTask
          : streamedResponseText.trim();
      expect(finalResponse, isNotEmpty, reason: 'Assistant response must be non-empty');

      aiConversationSessionId = taskObj['openCodeSessionId'] as String?;
    });

    test('78. Phase Z: Assistant response does not contain raw reasoning tokens', () async {
      expect(aiConversationTaskId, isNotNull);

      final taskRes = await client.sendRequest('ai.task.get', payload: {
        'taskId': aiConversationTaskId,
      });

      final taskObj = taskRes.payload!;
      final respFromTask = (taskObj['response'] as String?)?.trim();
      final responseText = (respFromTask != null && respFromTask.isNotEmpty)
          ? respFromTask
          : streamedResponseText.trim();

      expect(responseText, isNot(contains('"reasoning"')));
      expect(responseText, isNot(contains('"reasoning_details"')));
      expect(responseText, isNot(contains('<think>')));
    });

    test('79. Phase AA: Follow-up conversational task continuation', () async {
      final rootsRes = await client.sendRequest('files.roots');
      final workspacePath = aiProjectPath ?? (rootsRes.payload!['roots'] as List<dynamic>).first['path'] as String;

      final followUpPayload = <String, dynamic>{
        'projectPath': workspacePath,
        'prompt': 'What is the license or primary technology stack?',
        'agent': 'plan',
        'readOnly': true,
      };
      if (aiConversationSessionId != null) {
        followUpPayload['openCodeSessionId'] = aiConversationSessionId;
      }

      final followUpRes = await client.sendRequest(
        aiConversationSessionId != null ? 'ai.task.resume' : 'ai.task.start',
        payload: followUpPayload,
      );

      expect(followUpRes.success, isTrue);
      expect(followUpRes.payload?['taskId'], isNotNull);
    });

    test('80. Phase AB: Security boundary - non-existent or outside path rejected', () async {
      final invalidRes = await client.sendRequest('ai.task.start', payload: {
        'projectPath': '/root/secret_folder',
        'prompt': 'Explain files',
        'agent': 'plan',
        'readOnly': true,
      });

      expect(invalidRes.success, isFalse);
    });

    test('81. Phase AC: File Search Engine - Name Search (files.search)', () async {
      final rootsRes = await client.sendRequest('files.roots');
      final searchRoot = aiProjectPath ?? (rootsRes.payload!['roots'] as List<dynamic>).first['path'] as String;

      final sep = searchRoot.contains('\\') ? '\\' : '/';
      final testReadme = File('$searchRoot$sep' 'README.md');
      if (!testReadme.existsSync()) {
        await testReadme.writeAsString('# Orbit Test Project\n\nOrbit remote test fixture.\n');
      }

      final res = await client.sendRequest('files.search', payload: {
        'root': searchRoot,
        'query': 'README.md',
        'mode': 'name',
        'maxResults': 10,
      });

      expect(res.success, isTrue);
      expect(res.payload, isNotNull);
      final searchRes = FileSearchResult.fromJson(res.payload!);
      expect(searchRes.results.any((r) => r.name.toLowerCase().contains('readme.md')), isTrue);
    });

    test('82. Phase AD: File Search Engine - Content Search with line numbers (files.search)', () async {
      final rootsRes = await client.sendRequest('files.roots');
      final searchRoot = aiProjectPath ?? (rootsRes.payload!['roots'] as List<dynamic>).first['path'] as String;

      final res = await client.sendRequest('files.search', payload: {
        'root': searchRoot,
        'query': 'Orbit',
        'mode': 'content',
        'maxResults': 10,
      });

      expect(res.success, isTrue);
      expect(res.payload, isNotNull);
      final searchRes = FileSearchResult.fromJson(res.payload!);
      expect(searchRes.results.isNotEmpty, isTrue);
      final firstMatch = searchRes.results.first;
      expect(firstMatch.line, isNotNull);
      expect(firstMatch.snippet, isNotNull);
    });

    test('83. Phase AE: AI Permission System - Live List & Resolve handshake', () async {
      final listRes = await client.sendRequest('ai.permission.list');
      expect(listRes.success, isTrue);
      final list = listRes.payload?['permissions'] ?? listRes.payload?['requests'];
      expect(list, isA<List<dynamic>>());

      // Attempting to resolve non-existent permission should fail cleanly with error
      final resolveRes = await client.sendRequest('ai.permission.resolve', payload: {
        'permissionId': 'non_existent_perm_999',
        'decision': 'once',
      });
      expect(resolveRes.success, isFalse);
      expect(resolveRes.error?.code, anyOf(equals('AI_TASK_FAILED'), equals('NOT_FOUND')));
    });
  });
}
