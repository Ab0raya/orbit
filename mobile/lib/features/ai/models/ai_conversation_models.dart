import '../../../protocol/models/ai_models.dart';

class OrbitConversation {
  final String id;
  final String title;
  final int createdAt;
  final int updatedAt;
  final String? projectPath;
  final String? directoryPath;
  final String contextType;
  final String? openCodeSessionId;
  final String? providerId;
  final String? modelId;
  final String status;
  final String? lastMessagePreview;
  final int messageCount;

  const OrbitConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.projectPath,
    this.directoryPath,
    this.contextType = 'project',
    this.openCodeSessionId,
    this.providerId,
    this.modelId,
    this.status = 'active',
    this.lastMessagePreview,
    this.messageCount = 0,
  });

  factory OrbitConversation.fromJson(Map<String, dynamic> json) {
    // Backend serializes camelCase (serde rename_all); accept snake_case
    // only as a legacy fallback. Dropping either side silently loses the
    // session/model/provier mapping on restore.
    return OrbitConversation(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Conversation',
      createdAt: (json['createdAt'] ?? json['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] ?? json['updated_at'] as num?)?.toInt() ?? 0,
      projectPath: json['projectPath'] as String? ?? json['project_path'] as String?,
      directoryPath: json['directoryPath'] as String? ?? json['directory_path'] as String?,
      contextType: json['contextType'] as String? ?? json['context_type'] as String? ?? 'project',
      openCodeSessionId: json['openCodeSessionId'] as String? ?? json['open_code_session_id'] as String?,
      providerId: json['providerId'] as String? ?? json['provider_id'] as String?,
      modelId: json['modelId'] as String? ?? json['model_id'] as String?,
      status: json['status'] as String? ?? 'active',
      lastMessagePreview: json['lastMessagePreview'] as String? ?? json['last_message_preview'] as String?,
      messageCount: (json['messageCount'] ?? json['message_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'project_path': projectPath,
        'directory_path': directoryPath,
        'context_type': contextType,
        'open_code_session_id': openCodeSessionId,
        'provider_id': providerId,
        'model_id': modelId,
        'status': status,
        'last_message_preview': lastMessagePreview,
        'message_count': messageCount,
      };

  OrbitConversation copyWith({
    String? id,
    String? title,
    int? createdAt,
    int? updatedAt,
    String? projectPath,
    String? directoryPath,
    String? contextType,
    String? openCodeSessionId,
    String? providerId,
    String? modelId,
    String? status,
    String? lastMessagePreview,
    int? messageCount,
  }) {
    return OrbitConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      projectPath: projectPath ?? this.projectPath,
      directoryPath: directoryPath ?? this.directoryPath,
      contextType: contextType ?? this.contextType,
      openCodeSessionId: openCodeSessionId ?? this.openCodeSessionId,
      providerId: providerId ?? this.providerId,
      modelId: modelId ?? this.modelId,
      status: status ?? this.status,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      messageCount: messageCount ?? this.messageCount,
    );
  }
}

class OrbitConversationMessage {
  final String id;
  final String conversationId;
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final int createdAt;
  final String status;
  final String? taskId;
  final String? providerId;
  final String? modelId;
  final List<AiActivity> activities;
  final String? error;

  const OrbitConversationMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = 'completed',
    this.taskId,
    this.providerId,
    this.modelId,
    this.activities = const [],
    this.error,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  factory OrbitConversationMessage.fromJson(Map<String, dynamic> json) {
    var rawActs = json['activities'] as List<dynamic>?;
    List<AiActivity> actList = [];
    if (rawActs != null) {
      actList = rawActs
          .whereType<Map<String, dynamic>>()
          .map((m) => AiActivity.fromJson(m))
          .toList();
    }

    return OrbitConversationMessage(
      id: json['id'] as String? ?? '',
      conversationId: json['conversationId'] as String? ?? json['conversation_id'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      createdAt: (json['createdAt'] ?? json['created_at'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'completed',
      taskId: json['taskId'] as String? ?? json['task_id'] as String?,
      providerId: json['providerId'] as String? ?? json['provider_id'] as String?,
      modelId: json['modelId'] as String? ?? json['model_id'] as String?,
      activities: actList,
      error: json['error'] as String?,
    );
  }
}

class OrbitConversationDetail {
  final OrbitConversation summary;
  final List<OrbitConversationMessage> messages;

  const OrbitConversationDetail({
    required this.summary,
    required this.messages,
  });

  factory OrbitConversationDetail.fromJson(Map<String, dynamic> json) {
    var rawMsgs = json['messages'] as List<dynamic>? ?? [];
    var msgList = rawMsgs
        .whereType<Map<String, dynamic>>()
        .map((m) => OrbitConversationMessage.fromJson(m))
        .toList();

    return OrbitConversationDetail(
      summary: OrbitConversation.fromJson(json),
      messages: msgList,
    );
  }
}

class OrbitProviderSummary {
  final String providerId;
  final String name;
  final bool connected;
  final String authMethod;
  final String? maskedCredential;
  final String? lastVerified;
  final String? error;

  const OrbitProviderSummary({
    required this.providerId,
    required this.name,
    required this.connected,
    required this.authMethod,
    this.maskedCredential,
    this.lastVerified,
    this.error,
  });

  factory OrbitProviderSummary.fromJson(Map<String, dynamic> json) {
    return OrbitProviderSummary(
      providerId: json['providerId'] as String? ?? json['provider_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      connected: json['connected'] as bool? ?? false,
      authMethod: json['authMethod'] as String? ?? json['auth_method'] as String? ?? 'api_key',
      maskedCredential: json['maskedCredential'] as String? ?? json['masked_credential'] as String?,
      lastVerified: json['lastVerified']?.toString() ?? json['last_verified']?.toString(),
      error: json['error'] as String?,
    );
  }
}

class OrbitModelSummary {
  final String id;
  final String name;
  final String provider;
  final int? contextWindow;
  final bool supportsTools;
  final bool supportsStreaming;
  final bool defaultModel;

  const OrbitModelSummary({
    required this.id,
    required this.name,
    required this.provider,
    this.contextWindow,
    this.supportsTools = true,
    this.supportsStreaming = true,
    this.defaultModel = false,
  });

  factory OrbitModelSummary.fromJson(Map<String, dynamic> json) {
    return OrbitModelSummary(
      id: json['modelId'] as String? ?? json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      provider: json['providerId'] as String? ?? json['provider'] as String? ?? '',
      contextWindow: (json['contextWindow'] ?? json['context_window'] as num?)?.toInt(),
      supportsTools: json['supportsTools'] as bool? ?? json['supports_tools'] as bool? ?? true,
      supportsStreaming: json['supportsStreaming'] as bool? ?? json['supports_streaming'] as bool? ?? true,
      defaultModel: json['defaultModel'] as bool? ?? json['default_model'] as bool? ?? false,
    );
  }
}

class OrbitAiDefaults {
  final String? defaultProvider;
  final String? defaultModel;
  final String? defaultAgent;
  final String? defaultContextBehavior;

  const OrbitAiDefaults({
    this.defaultProvider,
    this.defaultModel,
    this.defaultAgent,
    this.defaultContextBehavior,
  });

  factory OrbitAiDefaults.fromJson(Map<String, dynamic> json) {
    return OrbitAiDefaults(
      defaultProvider: json['providerId'] as String? ?? json['default_provider'] as String?,
      defaultModel: json['modelId'] as String? ?? json['default_model'] as String?,
      defaultAgent: json['agent'] as String? ?? json['default_agent'] as String?,
      defaultContextBehavior: json['contextBehavior'] as String? ?? json['default_context_behavior'] as String?,
    );
  }
}
