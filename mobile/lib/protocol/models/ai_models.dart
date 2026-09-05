enum AiAgent {
  plan,
  build;

  static AiAgent fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'build':
        return AiAgent.build;
      case 'plan':
      default:
        return AiAgent.plan;
    }
  }

  String toServerString() => name;
}

enum AiTaskStatus {
  queued,
  running,
  completed,
  failed,
  cancelled;

  static AiTaskStatus fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'running':
        return AiTaskStatus.running;
      case 'completed':
        return AiTaskStatus.completed;
      case 'failed':
        return AiTaskStatus.failed;
      case 'cancelled':
        return AiTaskStatus.cancelled;
      case 'queued':
      default:
        return AiTaskStatus.queued;
    }
  }

  bool get isTerminal =>
      this == AiTaskStatus.completed ||
      this == AiTaskStatus.failed ||
      this == AiTaskStatus.cancelled;
}

enum AiActivityType {
  thinking,
  reading,
  writing,
  command,
  testing,
  tool,
  waiting,
  permissionRequired,
  completed,
  error;

  static AiActivityType fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'thinking':
        return AiActivityType.thinking;
      case 'reading':
        return AiActivityType.reading;
      case 'writing':
        return AiActivityType.writing;
      case 'command':
        return AiActivityType.command;
      case 'testing':
        return AiActivityType.testing;
      case 'tool':
        return AiActivityType.tool;
      case 'waiting':
        return AiActivityType.waiting;
      case 'permissionrequired':
      case 'permission_required':
        return AiActivityType.permissionRequired;
      case 'completed':
        return AiActivityType.completed;
      case 'error':
        return AiActivityType.error;
      default:
        return AiActivityType.tool;
    }
  }

  String toServerString() => name;
}

enum AiActivityStatus {
  running,
  completed,
  failed;

  static AiActivityStatus fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'completed':
        return AiActivityStatus.completed;
      case 'failed':
        return AiActivityStatus.failed;
      case 'running':
      default:
        return AiActivityStatus.running;
    }
  }

  String toServerString() => name;
}

class AiToolActivity {
  final String tool;
  final String status;
  final String? title;
  final int? exitCode;
  final DateTime timestamp;

  AiToolActivity({
    required this.tool,
    required this.status,
    this.title,
    this.exitCode,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory AiToolActivity.fromJson(Map<String, dynamic> json) {
    return AiToolActivity(
      tool: json['tool'] as String? ?? 'unknown',
      status: json['status'] as String? ?? 'running',
      title: json['title'] as String?,
      exitCode: json['exitCode'] as int?,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'tool': tool,
        'status': status,
        if (title != null) 'title': title,
        if (exitCode != null) 'exitCode': exitCode,
        'timestamp': timestamp.toIso8601String(),
      };
}

class AiActivity {
  final String activityId;
  final String taskId;
  final int timestamp; // Milliseconds since epoch
  final AiActivityType activityType;
  final AiActivityStatus status;
  final String title;
  final String? detail;
  final String? tool;
  final String? command;
  final String? filePath;
  final int? durationMs;
  final int? exitCode;

  AiActivity({
    required this.activityId,
    this.taskId = '',
    int? timestamp,
    this.activityType = AiActivityType.tool,
    this.status = AiActivityStatus.completed,
    required this.title,
    this.detail,
    this.tool,
    this.command,
    this.filePath,
    this.durationMs,
    this.exitCode,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  // Compatibility getters
  String get id => activityId;
  String get type => activityType.name;
  String get description => title;

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(
        timestamp > 1000000000000 ? timestamp : timestamp * 1000,
      );

  factory AiActivity.fromJson(Map<String, dynamic> json) {
    final actType = json['activityType'] != null
        ? AiActivityType.fromString(json['activityType'].toString())
        : (json['type'] != null
            ? AiActivityType.fromString(json['type'].toString())
            : AiActivityType.tool);

    final actStatus = json['status'] != null
        ? AiActivityStatus.fromString(json['status'].toString())
        : AiActivityStatus.completed;

    int parseTimestamp(dynamic ts) {
      if (ts is int) return ts;
      if (ts is String) {
        final parsed = DateTime.tryParse(ts);
        if (parsed != null) return parsed.millisecondsSinceEpoch;
        final asInt = int.tryParse(ts);
        if (asInt != null) return asInt;
      }
      return DateTime.now().millisecondsSinceEpoch;
    }

    String? toolStr;
    if (json['tool'] is String) {
      toolStr = json['tool'] as String;
    } else if (json['tool'] is Map<String, dynamic>) {
      toolStr = (json['tool'] as Map<String, dynamic>)['tool'] as String?;
    }

    return AiActivity(
      activityId: (json['activityId'] ?? json['id'] ?? '') as String,
      taskId: json['taskId'] as String? ?? '',
      timestamp: parseTimestamp(json['timestamp']),
      activityType: actType,
      status: actStatus,
      title: (json['title'] ?? json['description'] ?? '') as String,
      detail: json['detail'] as String?,
      tool: toolStr,
      command: json['command'] as String?,
      filePath: json['filePath'] as String?,
      durationMs: json['durationMs'] as int?,
      exitCode: json['exitCode'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'activityId': activityId,
        'taskId': taskId,
        'timestamp': timestamp,
        'activityType': activityType.toServerString(),
        'status': status.toServerString(),
        'title': title,
        if (detail != null) 'detail': detail,
        if (tool != null) 'tool': tool,
        if (command != null) 'command': command,
        if (filePath != null) 'filePath': filePath,
        if (durationMs != null) 'durationMs': durationMs,
        if (exitCode != null) 'exitCode': exitCode,
        // Compatibility keys
        'id': activityId,
        'type': activityType.name,
        'description': title,
      };

  AiActivity copyWith({
    String? activityId,
    String? taskId,
    int? timestamp,
    AiActivityType? activityType,
    AiActivityStatus? status,
    String? title,
    String? detail,
    String? tool,
    String? command,
    String? filePath,
    int? durationMs,
    int? exitCode,
  }) {
    return AiActivity(
      activityId: activityId ?? this.activityId,
      taskId: taskId ?? this.taskId,
      timestamp: timestamp ?? this.timestamp,
      activityType: activityType ?? this.activityType,
      status: status ?? this.status,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      tool: tool ?? this.tool,
      command: command ?? this.command,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
      exitCode: exitCode ?? this.exitCode,
    );
  }
}

class AiTask {
  final String taskId;
  final String projectPath;
  final AiTaskStatus status;
  final AiAgent agent;
  final bool readOnly;
  final String? openCodeSessionId;
  final int startedAt;
  final int? finishedAt;
  final String? output;
  final String? response;
  final String? error;
  final String? prompt;
  final List<AiActivity> activities;

  const AiTask({
    required this.taskId,
    required this.projectPath,
    required this.status,
    required this.agent,
    required this.readOnly,
    this.openCodeSessionId,
    required this.startedAt,
    this.finishedAt,
    this.output,
    this.response,
    this.error,
    this.prompt,
    this.activities = const [],
  });

  factory AiTask.fromJson(Map<String, dynamic> json) {
    final rawActivities = json['activities'];
    List<AiActivity> parsedActivities = const [];
    if (rawActivities is List) {
      parsedActivities = rawActivities
          .map((a) => AiActivity.fromJson(a as Map<String, dynamic>))
          .toList();
    }

    return AiTask(
      taskId: json['taskId'] as String? ?? '',
      projectPath: json['projectPath'] as String? ?? '',
      status: AiTaskStatus.fromString(json['status'] as String? ?? 'queued'),
      agent: AiAgent.fromString(json['agent'] as String? ?? 'plan'),
      readOnly: json['readOnly'] as bool? ?? true,
      openCodeSessionId: json['openCodeSessionId'] as String?,
      startedAt: json['startedAt'] as int? ?? 0,
      finishedAt: json['finishedAt'] as int?,
      output: json['output'] as String?,
      response: json['response'] as String?,
      error: json['error'] as String?,
      prompt: json['prompt'] as String?,
      activities: parsedActivities,
    );
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'projectPath': projectPath,
        'status': status.name,
        'agent': agent.name,
        'readOnly': readOnly,
        if (openCodeSessionId != null) 'openCodeSessionId': openCodeSessionId,
        'startedAt': startedAt,
        if (finishedAt != null) 'finishedAt': finishedAt,
        if (output != null) 'output': output,
        if (response != null) 'response': response,
        if (error != null) 'error': error,
        if (prompt != null) 'prompt': prompt,
        'activities': activities.map((a) => a.toJson()).toList(),
      };

  AiTask copyWith({
    String? taskId,
    String? projectPath,
    AiTaskStatus? status,
    AiAgent? agent,
    bool? readOnly,
    String? openCodeSessionId,
    int? startedAt,
    int? finishedAt,
    String? output,
    String? response,
    String? error,
    String? prompt,
    List<AiActivity>? activities,
  }) {
    return AiTask(
      taskId: taskId ?? this.taskId,
      projectPath: projectPath ?? this.projectPath,
      status: status ?? this.status,
      agent: agent ?? this.agent,
      readOnly: readOnly ?? this.readOnly,
      openCodeSessionId: openCodeSessionId ?? this.openCodeSessionId,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      output: output ?? this.output,
      response: response ?? this.response,
      error: error ?? this.error,
      prompt: prompt ?? this.prompt,
      activities: activities ?? this.activities,
    );
  }

  String get displayPrompt =>
      prompt != null && prompt!.isNotEmpty ? prompt! : (activities.isNotEmpty ? activities.first.title : 'AI Task');
}

class AiTaskSummary {
  final String taskId;
  final String projectPath;
  final AiTaskStatus status;
  final AiAgent agent;
  final bool readOnly;
  final String? openCodeSessionId;
  final int startedAt;
  final int? finishedAt;
  final int activityCount;
  final String? latestActivity;

  const AiTaskSummary({
    required this.taskId,
    required this.projectPath,
    required this.status,
    required this.agent,
    required this.readOnly,
    this.openCodeSessionId,
    required this.startedAt,
    this.finishedAt,
    this.activityCount = 0,
    this.latestActivity,
  });

  factory AiTaskSummary.fromJson(Map<String, dynamic> json) {
    return AiTaskSummary(
      taskId: json['taskId'] as String? ?? '',
      projectPath: json['projectPath'] as String? ?? '',
      status: AiTaskStatus.fromString(json['status'] as String? ?? 'queued'),
      agent: AiAgent.fromString(json['agent'] as String? ?? 'plan'),
      readOnly: json['readOnly'] as bool? ?? true,
      openCodeSessionId: json['openCodeSessionId'] as String?,
      startedAt: json['startedAt'] as int? ?? 0,
      finishedAt: json['finishedAt'] as int?,
      activityCount: json['activityCount'] as int? ?? 0,
      latestActivity: json['latestActivity'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'projectPath': projectPath,
        'status': status.name,
        'agent': agent.name,
        'readOnly': readOnly,
        if (openCodeSessionId != null) 'openCodeSessionId': openCodeSessionId,
        'startedAt': startedAt,
        if (finishedAt != null) 'finishedAt': finishedAt,
        'activityCount': activityCount,
        if (latestActivity != null) 'latestActivity': latestActivity,
      };
}
