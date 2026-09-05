enum AiPermissionRisk {
  low,
  medium,
  high;

  static AiPermissionRisk fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'high':
        return AiPermissionRisk.high;
      case 'medium':
        return AiPermissionRisk.medium;
      case 'low':
      default:
        return AiPermissionRisk.low;
    }
  }
}

enum AiPermissionState {
  pending,
  approved,
  denied,
  expired,
  cancelled;

  static AiPermissionState fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'approved':
        return AiPermissionState.approved;
      case 'denied':
        return AiPermissionState.denied;
      case 'expired':
        return AiPermissionState.expired;
      case 'cancelled':
        return AiPermissionState.cancelled;
      case 'pending':
      default:
        return AiPermissionState.pending;
    }
  }
}

class AiPermissionRequest {
  final String permissionId;
  final String taskId;
  final String deviceId;
  final String? sessionId;
  final String tool;
  final String action;
  final String target;
  final List<String> patterns;
  final String projectPath;
  final AiPermissionRisk risk;
  final AiPermissionState state;
  final Map<String, dynamic> metadata;
  final int createdAt;
  final int timeoutAt;

  const AiPermissionRequest({
    required this.permissionId,
    required this.taskId,
    required this.deviceId,
    this.sessionId,
    required this.tool,
    required this.action,
    required this.target,
    this.patterns = const [],
    required this.projectPath,
    required this.risk,
    required this.state,
    this.metadata = const {},
    required this.createdAt,
    required this.timeoutAt,
  });

  bool get isPending => state == AiPermissionState.pending;
  bool get isHighRisk => risk == AiPermissionRisk.high;

  factory AiPermissionRequest.fromJson(Map<String, dynamic> json) {
    final patternsRaw = json['patterns'] as List<dynamic>? ?? [];
    return AiPermissionRequest(
      permissionId: json['permissionId'] as String? ?? json['id'] as String? ?? '',
      taskId: json['taskId'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      sessionId: json['sessionId'] as String?,
      tool: json['tool'] as String? ?? '',
      action: json['action'] as String? ?? '',
      target: json['target'] as String? ?? '',
      patterns: patternsRaw.map((p) => p.toString()).toList(),
      projectPath: json['projectPath'] as String? ?? '',
      risk: AiPermissionRisk.fromString(json['risk'] as String? ?? 'medium'),
      state: AiPermissionState.fromString(json['state'] as String? ?? 'pending'),
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      timeoutAt: (json['timeoutAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'permissionId': permissionId,
        'taskId': taskId,
        'deviceId': deviceId,
        if (sessionId != null) 'sessionId': sessionId,
        'tool': tool,
        'action': action,
        'target': target,
        'patterns': patterns,
        'projectPath': projectPath,
        'risk': risk.name,
        'state': state.name,
        'metadata': metadata,
        'createdAt': createdAt,
        'timeoutAt': timeoutAt,
      };

  AiPermissionRequest copyWith({
    String? permissionId,
    String? taskId,
    String? deviceId,
    String? sessionId,
    String? tool,
    String? action,
    String? target,
    List<String>? patterns,
    String? projectPath,
    AiPermissionRisk? risk,
    AiPermissionState? state,
    Map<String, dynamic>? metadata,
    int? createdAt,
    int? timeoutAt,
  }) {
    return AiPermissionRequest(
      permissionId: permissionId ?? this.permissionId,
      taskId: taskId ?? this.taskId,
      deviceId: deviceId ?? this.deviceId,
      sessionId: sessionId ?? this.sessionId,
      tool: tool ?? this.tool,
      action: action ?? this.action,
      target: target ?? this.target,
      patterns: patterns ?? this.patterns,
      projectPath: projectPath ?? this.projectPath,
      risk: risk ?? this.risk,
      state: state ?? this.state,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      timeoutAt: timeoutAt ?? this.timeoutAt,
    );
  }
}
