class Script {
  final String id;
  final String name;
  final String? description;
  final String content;
  final String? workingDirectory;
  final String? projectPath;
  final int createdAt;
  final int updatedAt;

  const Script({
    required this.id,
    required this.name,
    this.description,
    required this.content,
    this.workingDirectory,
    this.projectPath,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isGlobal => projectPath == null || projectPath!.isEmpty;

  factory Script.fromJson(Map<String, dynamic> json) {
    return Script(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      content: json['content'] as String? ?? '',
      workingDirectory: json['workingDirectory'] as String?,
      projectPath: json['projectPath'] as String?,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'content': content,
      'workingDirectory': workingDirectory,
      'projectPath': projectPath,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  Script copyWith({
    String? id,
    String? name,
    String? description,
    String? content,
    String? workingDirectory,
    String? projectPath,
    int? createdAt,
    int? updatedAt,
  }) {
    return Script(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      content: content ?? this.content,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      projectPath: projectPath ?? this.projectPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ScriptInput {
  final String? id;
  final String name;
  final String? description;
  final String content;
  final String? workingDirectory;
  final String? projectPath;

  const ScriptInput({
    this.id,
    required this.name,
    this.description,
    required this.content,
    this.workingDirectory,
    this.projectPath,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      if (description != null) 'description': description,
      'content': content,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
      if (projectPath != null) 'projectPath': projectPath,
    };
  }
}
