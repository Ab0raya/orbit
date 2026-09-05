import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/core/networking/orbit_websocket_client.dart';
import 'package:orbit_mobile/features/ai/controllers/ai_task_controller.dart';
import 'package:orbit_mobile/protocol/messages/orbit_event.dart';
import 'package:orbit_mobile/protocol/models/ai_models.dart';

void main() {
  group('AI Models & Serialization Tests', () {
    test('1. AiAgent enum parsing and properties', () {
      expect(AiAgent.fromString('plan'), AiAgent.plan);
      expect(AiAgent.fromString('PLAN'), AiAgent.plan);
      expect(AiAgent.fromString('build'), AiAgent.build);
      expect(AiAgent.fromString('BUILD'), AiAgent.build);
      expect(AiAgent.fromString('unknown'), AiAgent.plan);

      expect(AiAgent.plan.toServerString(), 'plan');
      expect(AiAgent.build.toServerString(), 'build');
    });

    test('2. AiTaskStatus enum transitions & isTerminal', () {
      expect(AiTaskStatus.queued.isTerminal, isFalse);
      expect(AiTaskStatus.running.isTerminal, isFalse);
      expect(AiTaskStatus.completed.isTerminal, isTrue);
      expect(AiTaskStatus.failed.isTerminal, isTrue);
      expect(AiTaskStatus.cancelled.isTerminal, isTrue);

      expect(AiTaskStatus.fromString('running'), AiTaskStatus.running);
      expect(AiTaskStatus.fromString('completed'), AiTaskStatus.completed);
      expect(AiTaskStatus.fromString('failed'), AiTaskStatus.failed);
      expect(AiTaskStatus.fromString('cancelled'), AiTaskStatus.cancelled);
      expect(AiTaskStatus.fromString('queued'), AiTaskStatus.queued);
    });

    test('3. AiActivityType and AiActivityStatus parsing', () {
      expect(AiActivityType.fromString('command'), AiActivityType.command);
      expect(AiActivityType.fromString('testing'), AiActivityType.testing);
      expect(AiActivityType.fromString('reading'), AiActivityType.reading);
      expect(AiActivityType.fromString('writing'), AiActivityType.writing);
      expect(AiActivityType.fromString('thinking'), AiActivityType.thinking);
      expect(AiActivityType.fromString('completed'), AiActivityType.completed);
      expect(AiActivityType.fromString('error'), AiActivityType.error);
      expect(AiActivityType.fromString('other'), AiActivityType.tool);

      expect(AiActivityStatus.fromString('running'), AiActivityStatus.running);
      expect(AiActivityStatus.fromString('completed'), AiActivityStatus.completed);
      expect(AiActivityStatus.fromString('failed'), AiActivityStatus.failed);
    });

    test('4. AiActivity serialization with Milestone 08 fields', () {
      final activity = AiActivity(
        activityId: 'act_101',
        taskId: 'task_001',
        timestamp: 1700000000000,
        activityType: AiActivityType.command,
        status: AiActivityStatus.completed,
        title: 'Running tests',
        detail: 'Executing test suite',
        tool: 'bash',
        command: 'flutter test',
        filePath: 'test/unit_test.dart',
        durationMs: 4200,
        exitCode: 0,
      );

      final json = activity.toJson();
      expect(json['activityId'], 'act_101');
      expect(json['taskId'], 'task_001');
      expect(json['activityType'], 'command');
      expect(json['status'], 'completed');
      expect(json['title'], 'Running tests');
      expect(json['tool'], 'bash');
      expect(json['command'], 'flutter test');
      expect(json['filePath'], 'test/unit_test.dart');
      expect(json['durationMs'], 4200);
      expect(json['exitCode'], 0);

      final fromJson = AiActivity.fromJson(json);
      expect(fromJson.activityId, 'act_101');
      expect(fromJson.taskId, 'task_001');
      expect(fromJson.activityType, AiActivityType.command);
      expect(fromJson.status, AiActivityStatus.completed);
      expect(fromJson.title, 'Running tests');
      expect(fromJson.tool, 'bash');
      expect(fromJson.command, 'flutter test');
      expect(fromJson.filePath, 'test/unit_test.dart');
      expect(fromJson.durationMs, 4200);
      expect(fromJson.exitCode, 0);

      // Backward-compatibility getters
      expect(fromJson.id, 'act_101');
      expect(fromJson.type, 'command');
      expect(fromJson.description, 'Running tests');
    });

    test('5. AiTask serialization including activities', () {
      final task = AiTask(
        taskId: 'task_001',
        projectPath: '/home/user/project',
        status: AiTaskStatus.running,
        agent: AiAgent.plan,
        readOnly: true,
        openCodeSessionId: 'ses_abc123',
        startedAt: 1000,
        activities: [
          AiActivity(
            activityId: 'act_init',
            taskId: 'task_001',
            title: 'Analyzing architecture',
            activityType: AiActivityType.thinking,
          ),
        ],
      );

      final json = task.toJson();
      expect(json['taskId'], 'task_001');
      expect(json['projectPath'], '/home/user/project');
      expect(json['status'], 'running');
      expect(json['agent'], 'plan');
      expect(json['readOnly'], true);
      expect(json['openCodeSessionId'], 'ses_abc123');
      expect(json['startedAt'], 1000);
      expect((json['activities'] as List).length, 1);

      final fromJson = AiTask.fromJson(json);
      expect(fromJson.taskId, 'task_001');
      expect(fromJson.activities.length, 1);
      expect(fromJson.activities.first.activityId, 'act_init');
      expect(fromJson.activities.first.title, 'Analyzing architecture');
    });
  });

  group('AiTaskController Event Handling Tests', () {
    test('6. Event stream updates controller state and currentActivity', () async {
      final client = OrbitWebSocketClient();
      final controller = AiTaskController(client);

      // Initial task
      final initialTask = AiTask(
        taskId: 'task_event_1',
        projectPath: '/test/proj',
        status: AiTaskStatus.queued,
        agent: AiAgent.plan,
        readOnly: true,
        startedAt: 1000,
      );
      controller.setActiveTask(initialTask);
      expect(controller.state.activeTask?.status, AiTaskStatus.queued);

      // Simulate ai.task.started
      final startedEv = OrbitEvent(
        type: 'event',
        event: 'ai.task.started',
        payload: {
          'taskId': 'task_event_1',
          'openCodeSessionId': 'ses_live_123',
        },
      );
      controller.handleOrbitEvent(startedEv.event, startedEv.payload);

      expect(controller.state.activeTask?.taskId, 'task_event_1');
      expect(controller.state.activeTask?.status, AiTaskStatus.running);
      expect(controller.state.activeTask?.openCodeSessionId, 'ses_live_123');

      // Simulate ai.task.activity (Milestone 08 normalized event)
      controller.handleOrbitEvent('ai.task.activity', {
        'taskId': 'task_event_1',
        'activity': {
          'activityId': 'act_live_01',
          'taskId': 'task_event_1',
          'timestamp': 1700000001000,
          'activityType': 'command',
          'status': 'running',
          'title': 'Running test suite',
          'command': 'flutter test',
        },
      });

      expect(controller.state.activities.last.activityId, 'act_live_01');
      expect(controller.state.activities.last.command, 'flutter test');
      expect(controller.state.currentActivity?.title, 'Running test suite');
      expect(controller.state.currentActivity?.activityType, AiActivityType.command);

      // Update same activity to completed
      controller.handleOrbitEvent('ai.task.activity', {
        'taskId': 'task_event_1',
        'activity': {
          'activityId': 'act_live_01',
          'taskId': 'task_event_1',
          'timestamp': 1700000005000,
          'activityType': 'command',
          'status': 'completed',
          'title': 'Tool bash exited (0)',
          'command': 'flutter test',
          'durationMs': 4000,
          'exitCode': 0,
        },
      });

      // Same activityId was updated, not duplicated
      final acts = controller.state.activities.where((a) => a.activityId == 'act_live_01').toList();
      expect(acts.length, 1);
      expect(acts.first.status, AiActivityStatus.completed);
      expect(acts.first.durationMs, 4000);

      // Simulate ai.task.output
      controller.handleOrbitEvent('ai.task.output', {
        'taskId': 'task_event_1',
        'text': '00:04 +18: All tests passed!\n',
      });
      expect(controller.state.accumulatedOutput, contains('All tests passed!'));

      // Simulate ai.task.completed
      controller.handleOrbitEvent('ai.task.completed', {
        'taskId': 'task_event_1',
        'output': '00:04 +18: All tests passed!\nCompleted.',
      });
      expect(controller.state.activeTask?.status, AiTaskStatus.completed);
      expect(controller.state.accumulatedOutput, contains('Completed.'));
    });

    test('7. Controller activity bounds enforcement (max 500)', () {
      final client = OrbitWebSocketClient();
      final controller = AiTaskController(client);

      final initialTask = AiTask(
        taskId: 'task_bound_mobile',
        projectPath: '/test/proj',
        status: AiTaskStatus.running,
        agent: AiAgent.plan,
        readOnly: true,
        startedAt: 1000,
      );
      controller.setActiveTask(initialTask);

      for (int i = 0; i < 550; i++) {
        controller.handleOrbitEvent('ai.task.activity', {
          'taskId': 'task_bound_mobile',
          'activity': {
            'activityId': 'act_$i',
            'taskId': 'task_bound_mobile',
            'timestamp': 1000 + i,
            'activityType': 'command',
            'status': 'completed',
            'title': 'Activity $i',
          },
        });
      }

      expect(controller.state.activities.length, AiTaskController.maxActivities);
      expect(controller.state.activities.first.activityId, 'act_50');
      expect(controller.state.activities.last.activityId, 'act_549');
    });

    test('8. Controller output bounds enforcement (max 256 KB)', () {
      final client = OrbitWebSocketClient();
      final controller = AiTaskController(client);

      final initialTask = AiTask(
        taskId: 'task_output_mobile',
        projectPath: '/test/proj',
        status: AiTaskStatus.running,
        agent: AiAgent.plan,
        readOnly: true,
        startedAt: 1000,
      );
      controller.setActiveTask(initialTask);

      final chunk = 'B' * 1024;
      for (int i = 0; i < 300; i++) {
        controller.handleOrbitEvent('ai.task.output', {
          'taskId': 'task_output_mobile',
          'text': chunk,
        });
      }
      controller.handleOrbitEvent('ai.task.output', {
        'taskId': 'task_output_mobile',
        'text': 'END_MARKER',
      });

      expect(controller.state.accumulatedOutput.length, lessThanOrEqualTo(AiTaskController.maxOutputBytes));
      expect(controller.state.accumulatedOutput, endsWith('END_MARKER'));
    });
  });
}
