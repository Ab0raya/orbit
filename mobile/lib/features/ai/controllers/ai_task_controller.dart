import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/orbit_websocket_client.dart';
import '../../../core/providers.dart';
import '../../../protocol/models/ai_models.dart';
import '../../../protocol/models/ai_context.dart';
import '../models/ai_message.dart';
import '../models/ai_conversation_models.dart';

class AiTaskState {
  final bool isLoading;
  final AiTask? activeTask;
  final List<AiActivity> activities;
  final List<AiTask> activeTasks;
  final String accumulatedOutput;
  final String? errorMessage;
  final AiContext currentContext;
  final List<AiMessage> messages;

  static const AiContext defaultContext = AiContext(
    source: AiContextSource.none,
    path: null,
    displayName: 'No context',
  );

  const AiTaskState({
    this.isLoading = false,
    this.activeTask,
    this.activities = const [],
    this.activeTasks = const [],
    this.accumulatedOutput = '',
    this.errorMessage,
    this.currentContext = defaultContext,
    this.messages = const [],
  });

  bool get isWorking =>
      isLoading ||
      (activeTask != null &&
          (activeTask!.status == AiTaskStatus.running ||
              activeTask!.status == AiTaskStatus.queued));

  AiActivity? get currentActivity {
    if (activities.isEmpty) return null;
    for (int i = activities.length - 1; i >= 0; i--) {
      if (activities[i].status == AiActivityStatus.running) {
        return activities[i];
      }
    }
    return activities.last;
  }

  AiTaskState copyWith({
    bool? isLoading,
    AiTask? activeTask,
    List<AiActivity>? activities,
    List<AiTask>? activeTasks,
    String? accumulatedOutput,
    String? errorMessage,
    AiContext? currentContext,
    List<AiMessage>? messages,
    bool clearError = false,
  }) {
    return AiTaskState(
      isLoading: isLoading ?? this.isLoading,
      activeTask: activeTask ?? this.activeTask,
      activities: activities ?? this.activities,
      activeTasks: activeTasks ?? this.activeTasks,
      accumulatedOutput: accumulatedOutput ?? this.accumulatedOutput,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      currentContext: currentContext ?? this.currentContext,
      messages: messages ?? this.messages,
    );
  }
}

class AiTaskController extends StateNotifier<AiTaskState> {
  final OrbitWebSocketClient _client;
  StreamSubscription? _eventSubscription;
  static const int maxActivities = 500;
  static const int maxOutputBytes = 256 * 1024;

  AiTaskController(this._client) : super(const AiTaskState()) {
    _subscribeEvents();
  }

  void _subscribeEvents() {
    _eventSubscription = _client.events.listen((event) {
      handleOrbitEvent(event.event, event.payload);
    });
  }

  void _addOrUpdateActivity(AiActivity activity) {
    final list = List<AiActivity>.from(state.activities);
    final idx = list.indexWhere((a) => a.activityId == activity.activityId);
    if (idx >= 0) {
      list[idx] = activity;
    } else {
      if (list.length >= maxActivities) {
        list.removeAt(0);
      }
      list.add(activity);
    }
    state = state.copyWith(activities: list);
  }

  void _updateAssistantActivity(String taskId, String title, [AiActivity? activity]) {
    final msgs = List<AiMessage>.from(state.messages);
    final idx = msgs.indexWhere(
        (m) => (m.taskId == taskId || m.taskId == null) && m.isAssistant);
    if (idx >= 0) {
      final msg = msgs[idx];
      final acts = List<AiActivity>.from(msg.activities);
      if (activity != null) {
        final aIdx = acts.indexWhere((a) => a.activityId == activity.activityId);
        if (aIdx >= 0) {
          acts[aIdx] = activity;
        } else {
          acts.add(activity);
        }
      }
      msgs[idx] = msg.copyWith(
        taskId: taskId,
        currentActivity: title,
        activities: acts,
        status: AiMessageStatus.working,
      );
      state = state.copyWith(messages: msgs);
    }
  }

  void handleOrbitEvent(String eventName, Map<String, dynamic> payload) {
    final taskId = payload['taskId'] as String?;
    if (taskId == null) return;

    final active = state.activeTask;
    final isOpenCodeSessionId = payload['openCodeSessionId'] as String?;

    switch (eventName) {
      case 'ai.task.created':
        final task = AiTask(
          taskId: taskId,
          projectPath: payload['projectPath'] as String? ?? '',
          status: AiTaskStatus.queued,
          agent: AiAgent.fromString(payload['agent'] as String? ?? 'plan'),
          readOnly: payload['readOnly'] as bool? ?? true,
          startedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        final initActivity = AiActivity(
          activityId: 'act_${DateTime.now().millisecondsSinceEpoch}',
          taskId: taskId,
          activityType: AiActivityType.waiting,
          status: AiActivityStatus.running,
          title: 'Task queued for execution',
        );

        // Update any pending assistant message with this taskId
        final msgs = List<AiMessage>.from(state.messages);
        final mIdx = msgs.indexWhere((m) => m.taskId == null && m.isAssistant);
        if (mIdx >= 0) {
          msgs[mIdx] = msgs[mIdx].copyWith(taskId: taskId);
        }

        state = state.copyWith(
          activeTask: task,
          activities: [initActivity],
          messages: msgs,
        );
        break;

      case 'ai.task.started':
        if (active != null && active.taskId == taskId) {
          final updatedTask = active.copyWith(
            status: AiTaskStatus.running,
            openCodeSessionId: isOpenCodeSessionId ?? active.openCodeSessionId,
          );

          final act = AiActivity(
            activityId: 'act_${DateTime.now().millisecondsSinceEpoch}',
            taskId: taskId,
            activityType: AiActivityType.thinking,
            status: AiActivityStatus.running,
            title: 'OpenCode process started',
          );
          _addOrUpdateActivity(act);
          _updateAssistantActivity(taskId, 'OpenCode process started', act);

          state = state.copyWith(activeTask: updatedTask);
        }
        break;

      case 'ai.task.response':
        final delta = payload['delta'] as String? ?? payload['text'] as String? ?? '';
        if (delta.isNotEmpty) {
          AiTask? updatedActiveTask = active;
          if (active != null && active.taskId == taskId) {
            final currentResp = active.response ?? '';
            updatedActiveTask = active.copyWith(response: currentResp + delta);
          }
          final msgs = List<AiMessage>.from(state.messages);
          final msgIndex = msgs.indexWhere((m) => m.taskId == taskId && m.isAssistant);
          if (msgIndex >= 0) {
            final targetMsg = msgs[msgIndex];
            msgs[msgIndex] = targetMsg.copyWith(
              text: targetMsg.text + delta,
              status: AiMessageStatus.working,
            );
          } else if (msgs.isNotEmpty &&
              msgs.last.isAssistant &&
              (msgs.last.taskId == null || msgs.last.taskId == taskId)) {
            final targetMsg = msgs.last;
            msgs[msgs.length - 1] = targetMsg.copyWith(
              taskId: taskId,
              text: targetMsg.text + delta,
              status: AiMessageStatus.working,
            );
          }
          state = state.copyWith(
            activeTask: updatedActiveTask,
            messages: msgs,
          );
        }
        break;

      case 'ai.task.activity':
        if (active != null && active.taskId == taskId) {
          final actJson = payload['activity'];
          if (actJson is Map<String, dynamic>) {
            final activity = AiActivity.fromJson(actJson);
            _addOrUpdateActivity(activity);
            _updateAssistantActivity(taskId, activity.title, activity);
            state = state.copyWith(
              activeTask: active.copyWith(
                openCodeSessionId: isOpenCodeSessionId ?? active.openCodeSessionId,
              ),
            );
          }
        }
        break;

      case 'ai.task.updated':
        if (active != null && active.taskId == taskId) {
          final activityText = payload['activity'] as String? ?? 'Thinking...';
          final act = AiActivity(
            activityId: 'act_${DateTime.now().millisecondsSinceEpoch}',
            taskId: taskId,
            activityType: AiActivityType.thinking,
            status: AiActivityStatus.running,
            title: activityText,
          );
          _addOrUpdateActivity(act);
          _updateAssistantActivity(taskId, activityText, act);

          state = state.copyWith(
            activeTask: active.copyWith(
              openCodeSessionId: isOpenCodeSessionId ?? active.openCodeSessionId,
            ),
          );
        }
        break;

      case 'ai.permission.requested':
        if (active != null && active.taskId == taskId) {
          final tool = payload['tool'] as String? ?? 'tool';
          final target = payload['target'] as String? ?? '';
          final title = 'Waiting for permission: $tool ${target.isNotEmpty ? "($target)" : ""}';
          final act = AiActivity(
            activityId: 'act_perm_${DateTime.now().millisecondsSinceEpoch}',
            taskId: taskId,
            activityType: AiActivityType.permissionRequired,
            status: AiActivityStatus.running,
            title: title,
            tool: tool,
            command: target,
          );
          _addOrUpdateActivity(act);
          _updateAssistantActivity(taskId, 'Waiting for permission', act);
          state = state.copyWith(activeTask: active);
        }
        break;

      case 'ai.permission.resolved':
        if (active != null && active.taskId == taskId) {
          final decision = payload['decision'] as String? ?? 'resolved';
          final reply = payload['reply'] as String? ?? decision;
          final isApproved = reply == 'once' || reply == 'always' || decision == 'allow' || decision == 'always';
          final title = isApproved ? 'Permission approved' : 'Permission denied';
          final act = AiActivity(
            activityId: 'act_perm_res_${DateTime.now().millisecondsSinceEpoch}',
            taskId: taskId,
            activityType: AiActivityType.permissionRequired,
            status: isApproved ? AiActivityStatus.completed : AiActivityStatus.failed,
            title: title,
          );
          _addOrUpdateActivity(act);
          _updateAssistantActivity(taskId, title, act);
          state = state.copyWith(activeTask: active);
        }
        break;

      case 'ai.task.tool_started':
        if (active != null && active.taskId == taskId) {
          final toolName = payload['tool'] as String? ?? 'tool';
          final title = payload['title'] as String?;
          final status = payload['status'] as String? ?? 'running';
          final command = payload['command'] as String?;
          final filePath = payload['filePath'] as String?;

          final isTesting = toolName == 'bash' &&
              (command != null && command.contains('test'));
          final isFileOp = toolName == 'read' || toolName == 'write' || filePath != null;

          AiActivityType type = AiActivityType.tool;
          if (isTesting) {
            type = AiActivityType.testing;
          } else if (toolName == 'bash' || command != null) {
            type = AiActivityType.command;
          } else if (isFileOp) {
            type = toolName == 'write' ? AiActivityType.writing : AiActivityType.reading;
          }

          final resolvedTitle = title ??
              (command != null
                  ? 'Running: $command'
                  : (filePath != null ? 'Using $toolName: $filePath' : 'Using $toolName'));

          final act = AiActivity(
            activityId: 'act_${DateTime.now().millisecondsSinceEpoch}',
            taskId: taskId,
            activityType: type,
            status: AiActivityStatus.fromString(status),
            title: resolvedTitle,
            tool: toolName,
            command: command,
            filePath: filePath,
          );

          _addOrUpdateActivity(act);
          _updateAssistantActivity(taskId, resolvedTitle, act);

          state = state.copyWith(
            activeTask: active.copyWith(
              openCodeSessionId: isOpenCodeSessionId ?? active.openCodeSessionId,
            ),
          );
        }
        break;

      case 'ai.task.tool_finished':
        if (active != null && active.taskId == taskId) {
          final toolName = payload['tool'] as String? ?? 'tool';
          final status = payload['status'] as String? ?? 'completed';
          final exitCode = payload['exitCode'] as int?;
          final durationMs = payload['durationMs'] as int?;
          final command = payload['command'] as String?;
          final filePath = payload['filePath'] as String?;

          final act = AiActivity(
            activityId: 'act_${DateTime.now().millisecondsSinceEpoch}',
            taskId: taskId,
            activityType: toolName == 'bash' ? AiActivityType.command : AiActivityType.tool,
            status: status == 'error' ? AiActivityStatus.failed : AiActivityStatus.completed,
            title: exitCode != null
                ? 'Tool $toolName exited ($exitCode)'
                : 'Tool $toolName finished',
            tool: toolName,
            command: command,
            filePath: filePath,
            durationMs: durationMs,
            exitCode: exitCode,
          );

          _addOrUpdateActivity(act);
          _updateAssistantActivity(taskId, act.title, act);
        }
        break;

      case 'ai.task.output':
        if (active != null && active.taskId == taskId) {
          final text = payload['text'] as String? ?? '';
          var newOutput = state.accumulatedOutput + text;
          if (newOutput.length > maxOutputBytes) {
            newOutput = newOutput.substring(newOutput.length - maxOutputBytes);
          }
          state = state.copyWith(accumulatedOutput: newOutput);
        }
        break;

      case 'ai.task.completed':
        if (active != null && active.taskId == taskId) {
          final payloadOutput = payload['output'] as String?;
          final finalOutput = (payloadOutput != null && payloadOutput.isNotEmpty)
              ? payloadOutput
              : (state.accumulatedOutput.isNotEmpty ? state.accumulatedOutput : null);

          final updatedTask = active.copyWith(
            status: AiTaskStatus.completed,
            finishedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            output: finalOutput,
            openCodeSessionId: isOpenCodeSessionId ?? active.openCodeSessionId,
          );

          _addOrUpdateActivity(AiActivity(
            activityId: 'act_${DateTime.now().millisecondsSinceEpoch}',
            taskId: taskId,
            activityType: AiActivityType.completed,
            status: AiActivityStatus.completed,
            title: 'Task completed successfully',
          ));

          // Complete assistant message
          final msgs = List<AiMessage>.from(state.messages);
          final mIdx = msgs.indexWhere(
              (m) => (m.taskId == taskId || m.taskId == null) && m.isAssistant);
          if (mIdx >= 0) {
            final msg = msgs[mIdx];
            var respText = msg.text;
            if (respText.trim().isEmpty) {
              final payloadResp = payload['response'] as String?;
              if (payloadResp != null && payloadResp.isNotEmpty) {
                respText = payloadResp;
              } else if (finalOutput != null && finalOutput.isNotEmpty) {
                respText = finalOutput;
              }
            }
            msgs[mIdx] = msg.copyWith(
              taskId: taskId,
              text: respText,
              status: AiMessageStatus.completed,
              currentActivity: 'Completed',
            );
          }

          state = state.copyWith(
            activeTask: updatedTask,
            accumulatedOutput: finalOutput ?? state.accumulatedOutput,
            messages: msgs,
            isLoading: false,
          );
        }
        break;

      case 'ai.task.failed':
        if (active != null && active.taskId == taskId) {
          final errorMsg = payload['error'] as String? ?? 'Task execution failed';
          final updatedTask = active.copyWith(
            status: AiTaskStatus.failed,
            finishedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            error: errorMsg,
            openCodeSessionId: isOpenCodeSessionId ?? active.openCodeSessionId,
          );

          _addOrUpdateActivity(AiActivity(
            activityId: 'act_${DateTime.now().millisecondsSinceEpoch}',
            taskId: taskId,
            activityType: AiActivityType.error,
            status: AiActivityStatus.failed,
            title: 'Task failed: $errorMsg',
          ));

          final msgs = List<AiMessage>.from(state.messages);
          final mIdx = msgs.indexWhere(
              (m) => (m.taskId == taskId || m.taskId == null) && m.isAssistant);
          if (mIdx >= 0) {
            msgs[mIdx] = msgs[mIdx].copyWith(
              taskId: taskId,
              status: AiMessageStatus.failed,
              error: errorMsg,
              currentActivity: 'Failed',
            );
          }

          state = state.copyWith(
            activeTask: updatedTask,
            errorMessage: errorMsg,
            messages: msgs,
            isLoading: false,
          );
        }
        break;

      case 'ai.task.cancelled':
        if (active != null && active.taskId == taskId) {
          final updatedTask = active.copyWith(
            status: AiTaskStatus.cancelled,
            finishedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            openCodeSessionId: isOpenCodeSessionId ?? active.openCodeSessionId,
          );

          _addOrUpdateActivity(AiActivity(
            activityId: 'act_${DateTime.now().millisecondsSinceEpoch}',
            taskId: taskId,
            activityType: AiActivityType.error,
            status: AiActivityStatus.failed,
            title: 'Task cancelled by user',
          ));

          final msgs = List<AiMessage>.from(state.messages);
          final mIdx = msgs.indexWhere(
              (m) => (m.taskId == taskId || m.taskId == null) && m.isAssistant);
          if (mIdx >= 0) {
            msgs[mIdx] = msgs[mIdx].copyWith(
              taskId: taskId,
              status: AiMessageStatus.failed,
              error: 'Task was cancelled',
              currentActivity: 'Cancelled',
            );
          }

          state = state.copyWith(
            activeTask: updatedTask,
            messages: msgs,
            isLoading: false,
          );
        }
        break;
    }
  }

  void setContext(AiContext context) {
    state = state.copyWith(currentContext: context);
  }

  void clearConversation() {
    state = state.copyWith(
      messages: [],
      activeTask: null,
      activities: [],
      accumulatedOutput: '',
      clearError: true,
    );
  }

  void loadConversationMessages(
    List<OrbitConversationMessage> convMessages, {
    String? openCodeSessionId,
    String? projectPath,
  }) {
    final msgs = convMessages.map((m) {
      return AiMessage(
        id: m.id,
        sender: m.isUser ? AiMessageSender.user : AiMessageSender.assistant,
        text: m.content,
        taskId: m.taskId,
        timestamp: DateTime.fromMillisecondsSinceEpoch(m.createdAt * 1000),
        status: m.status == 'failed'
            ? AiMessageStatus.failed
            : (m.status == 'running'
                ? AiMessageStatus.working
                : AiMessageStatus.completed),
        activities: m.activities,
        error: m.error,
      );
    }).toList();

    state = state.copyWith(
      messages: msgs,
      isLoading: false,
      activeTask: openCodeSessionId != null
          ? AiTask(
              taskId: 'task_resumed_${DateTime.now().millisecondsSinceEpoch}',
              projectPath: projectPath ?? '',
              status: AiTaskStatus.completed,
              agent: AiAgent.build,
              readOnly: false,
              startedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              openCodeSessionId: openCodeSessionId,
            )
          : null,
      activities: msgs.isNotEmpty ? msgs.last.activities : [],
    );
  }

  Future<AiTask?> sendMessage(
    String prompt, {
    AiContext? context,
    AiAgent agent = AiAgent.plan,
    bool readOnly = true,
    String? conversationId,
    String? model,
  }) async {
    final effectiveContext = context ?? state.currentContext;
    final userMsg = AiMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      sender: AiMessageSender.user,
      text: prompt,
      contextPath: effectiveContext.path,
      timestamp: DateTime.now(),
      status: AiMessageStatus.completed,
    );

    final assistantMsg = AiMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch + 1}',
      sender: AiMessageSender.assistant,
      text: '',
      contextPath: effectiveContext.path,
      timestamp: DateTime.now(),
      status: AiMessageStatus.working,
      currentActivity: 'Starting task...',
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg, assistantMsg],
      isLoading: true,
      clearError: true,
      activities: [],
      accumulatedOutput: '',
    );

    // If activeTask has an openCodeSessionId and matching path, try resuming session
    final canResume = state.activeTask?.openCodeSessionId != null &&
        (state.activeTask?.projectPath ?? '') == (effectiveContext.path ?? '');

    AiTask? task;
    if (canResume) {
      task = await resumeTask(
        state.activeTask!.openCodeSessionId!,
        effectiveContext.path ?? '',
        prompt,
        agent: agent,
        readOnly: readOnly,
        conversationId: conversationId,
        model: model,
      );
    }

    task ??= await startTask(
      effectiveContext.path,
      prompt,
      agent: agent,
      readOnly: readOnly,
      conversationId: conversationId,
      model: model,
    );

    if (task != null) {
      final msgs = List<AiMessage>.from(state.messages);
      final idx = msgs.indexWhere((m) => m.id == assistantMsg.id);
      if (idx >= 0) {
        msgs[idx] = msgs[idx].copyWith(taskId: task.taskId);
        state = state.copyWith(messages: msgs);
      }
    } else {
      final msgs = List<AiMessage>.from(state.messages);
      final idx = msgs.indexWhere((m) => m.id == assistantMsg.id);
      if (idx >= 0) {
        msgs[idx] = msgs[idx].copyWith(
          status: AiMessageStatus.failed,
          error: state.errorMessage ?? 'Failed to start AI task',
          currentActivity: 'Failed to launch',
        );
        state = state.copyWith(messages: msgs, isLoading: false);
      }
    }

    return task;
  }

  Future<AiTask?> startTask(
    String? projectPath,
    String prompt, {
    AiAgent agent = AiAgent.plan,
    bool readOnly = true,
    String? conversationId,
    String? model,
  }) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      activities: [],
      accumulatedOutput: '',
    );

    try {
      final payload = <String, dynamic>{
        'prompt': prompt,
        'agent': agent.toServerString(),
        'readOnly': readOnly,
      };
      if (projectPath != null && projectPath.isNotEmpty && projectPath != 'none') {
        payload['projectPath'] = projectPath;
      }
      if (conversationId != null) {
        payload['conversationId'] = conversationId;
      }
      if (model != null) {
        payload['model'] = model;
      }

      final response = await _client.sendRequest(
        'ai.task.start',
        payload: payload,
      );

      if (response.success && response.payload != null) {
        final task = AiTask.fromJson(response.payload!);
        state = state.copyWith(
          isLoading: false,
          activeTask: task,
          activities: task.activities,
        );
        return task;
      } else {
        final err = response.error?.message ?? 'Failed to start AI task';
        state = state.copyWith(
          isLoading: false,
          errorMessage: err,
        );
        return null;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  Future<AiTask?> resumeTask(
    String sessionID,
    String projectPath,
    String prompt, {
    AiAgent agent = AiAgent.plan,
    bool readOnly = true,
    String? conversationId,
    String? model,
  }) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      activities: [],
      accumulatedOutput: '',
    );

    try {
      final payload = <String, dynamic>{
        'openCodeSessionId': sessionID,
        'projectPath': projectPath,
        'prompt': prompt,
        'agent': agent.toServerString(),
        'readOnly': readOnly,
      };
      if (conversationId != null) {
        payload['conversationId'] = conversationId;
      }
      if (model != null) {
        payload['model'] = model;
      }

      final response = await _client.sendRequest(
        'ai.task.resume',
        payload: payload,
      );

      if (response.success && response.payload != null) {
        final task = AiTask.fromJson(response.payload!);
        state = state.copyWith(
          isLoading: false,
          activeTask: task,
          activities: task.activities,
        );
        return task;
      } else {
        final err = response.error?.message ?? 'Failed to resume AI session';
        state = state.copyWith(
          isLoading: false,
          errorMessage: err,
        );
        return null;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  Future<AiTask?> fetchTaskDetails(String taskId) async {
    try {
      final response = await _client.sendRequest(
        'ai.task.get',
        payload: {'taskId': taskId},
      );

      if (response.success && response.payload != null) {
        final task = AiTask.fromJson(response.payload!);
        state = state.copyWith(
          activeTask: task,
          activities: task.activities.isNotEmpty ? task.activities : state.activities,
          accumulatedOutput: task.output ?? state.accumulatedOutput,
        );
        return task;
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
    return null;
  }

  Future<bool> cancelTask(String taskId) async {
    try {
      final response = await _client.sendRequest(
        'ai.task.cancel',
        payload: {
          'taskId': taskId,
        },
      );

      if (response.success) {
        if (state.activeTask?.taskId == taskId) {
          state = state.copyWith(
            activeTask: state.activeTask?.copyWith(status: AiTaskStatus.cancelled),
          );
        }
        return true;
      } else {
        state = state.copyWith(
          errorMessage: response.error?.message ?? 'Failed to cancel task',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<void> loadActiveTasks() async {
    try {
      final response = await _client.sendRequest('ai.task.list');
      if (response.success && response.payload != null) {
        final list = response.payload!['tasks'] as List<dynamic>? ?? [];
        final tasks = list
            .map((item) => AiTask.fromJson(item as Map<String, dynamic>))
            .toList();

        state = state.copyWith(activeTasks: tasks);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  void setActiveTask(AiTask task) {
    state = state.copyWith(
      activeTask: task,
      activities: task.activities.isNotEmpty ? task.activities : state.activities,
      accumulatedOutput: task.output ?? state.accumulatedOutput,
    );
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

final aiTaskControllerProvider =
    StateNotifierProvider<AiTaskController, AiTaskState>((ref) {
  final client = ref.watch(webSocketClientProvider);
  return AiTaskController(client);
});
