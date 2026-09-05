import '../../../protocol/models/ai_models.dart';

enum AiMessageSender {
  user,
  assistant,
}

enum AiMessageStatus {
  idle,
  working,
  completed,
  failed,
}

class AiMessage {
  final String id;
  final AiMessageSender sender;
  final String text;
  final String? taskId;
  final String? contextPath;
  final DateTime timestamp;
  final AiMessageStatus status;
  final List<AiActivity> activities;
  final String? currentActivity;
  final String? error;

  const AiMessage({
    required this.id,
    required this.sender,
    required this.text,
    this.taskId,
    this.contextPath,
    required this.timestamp,
    this.status = AiMessageStatus.idle,
    this.activities = const [],
    this.currentActivity,
    this.error,
  });

  bool get isUser => sender == AiMessageSender.user;
  bool get isAssistant => sender == AiMessageSender.assistant;
  bool get isWorking => status == AiMessageStatus.working;

  AiMessage copyWith({
    String? id,
    AiMessageSender? sender,
    String? text,
    String? taskId,
    String? contextPath,
    DateTime? timestamp,
    AiMessageStatus? status,
    List<AiActivity>? activities,
    String? currentActivity,
    String? error,
  }) {
    return AiMessage(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      taskId: taskId ?? this.taskId,
      contextPath: contextPath ?? this.contextPath,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      activities: activities ?? this.activities,
      currentActivity: currentActivity ?? this.currentActivity,
      error: error ?? this.error,
    );
  }
}
