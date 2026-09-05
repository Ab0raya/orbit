enum AiContextSource {
  none,
  project,
  directory,
}

class AiContext {
  final AiContextSource source;
  final String? path;
  final String displayName;
  final String? projectId;
  final String? projectType;
  final bool isGit;

  const AiContext({
    required this.source,
    this.path,
    required this.displayName,
    this.projectId,
    this.projectType,
    this.isGit = false,
  });

  factory AiContext.none() {
    return const AiContext(
      source: AiContextSource.none,
      path: null,
      displayName: 'No context',
    );
  }

  factory AiContext.fromProject({
    required String path,
    required String name,
    String? projectType,
    bool isGit = false,
  }) {
    return AiContext(
      source: AiContextSource.project,
      path: path,
      displayName: name,
      projectId: name,
      projectType: projectType,
      isGit: isGit,
    );
  }

  factory AiContext.fromDirectory(String directoryPath) {
    final sep = directoryPath.contains('\\') ? '\\' : '/';
    final parts = directoryPath.split(sep).where((p) => p.isNotEmpty).toList();
    final name = parts.isNotEmpty ? parts.last : directoryPath;

    return AiContext(
      source: AiContextSource.directory,
      path: directoryPath,
      displayName: name,
      isGit: false,
    );
  }

  bool get isNone => source == AiContextSource.none;

  Map<String, dynamic> toJson() => {
        'source': source.name,
        'path': path,
        'displayName': displayName,
        'projectId': projectId,
        'projectType': projectType,
        'isGit': isGit,
      };

  factory AiContext.fromJson(Map<String, dynamic> json) {
    final sourceStr = json['source'] as String? ?? 'none';
    final source = AiContextSource.values.firstWhere(
      (s) => s.name == sourceStr,
      orElse: () => AiContextSource.none,
    );

    return AiContext(
      source: source,
      path: json['path'] as String?,
      displayName: json['displayName'] as String? ?? 'No context',
      projectId: json['projectId'] as String?,
      projectType: json['projectType'] as String?,
      isGit: json['isGit'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiContext &&
          runtimeType == other.runtimeType &&
          source == other.source &&
          path == other.path;

  @override
  int get hashCode => source.hashCode ^ (path?.hashCode ?? 0);
}
