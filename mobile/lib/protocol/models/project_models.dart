class ProjectRoot {
  final String name;
  final String path;

  const ProjectRoot({
    required this.name,
    required this.path,
  });

  factory ProjectRoot.fromJson(Map<String, dynamic> json) {
    return ProjectRoot(
      name: json['name'] as String? ?? 'Root',
      path: json['path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
      };
}

class ProjectGitSummary {
  final String branch;
  final bool isDirty;

  const ProjectGitSummary({
    required this.branch,
    required this.isDirty,
  });

  factory ProjectGitSummary.fromJson(Map<String, dynamic> json) {
    return ProjectGitSummary(
      branch: json['branch'] as String? ?? 'HEAD',
      isDirty: json['isDirty'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'branch': branch,
        'isDirty': isDirty,
      };
}

class ProjectSummary {
  final String name;
  final String path;
  final String kind; // "git" | "directory"
  final String projectType; // "flutter", "rust", "node", "python", "android", "generic"
  final ProjectGitSummary? git;

  const ProjectSummary({
    required this.name,
    required this.path,
    required this.kind,
    required this.projectType,
    this.git,
  });

  bool get isGit => kind == 'git';

  factory ProjectSummary.fromJson(Map<String, dynamic> json) {
    return ProjectSummary(
      name: json['name'] as String? ?? 'unnamed',
      path: json['path'] as String? ?? '',
      kind: json['kind'] as String? ?? 'directory',
      projectType: json['projectType'] as String? ?? 'generic',
      git: json['git'] != null
          ? ProjectGitSummary.fromJson(json['git'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'kind': kind,
        'projectType': projectType,
        if (git != null) 'git': git!.toJson(),
      };
}

class GitFileChange {
  final String path;
  final String status; // "modified", "added", "deleted", "renamed", "untracked"

  const GitFileChange({
    required this.path,
    required this.status,
  });

  factory GitFileChange.fromJson(Map<String, dynamic> json) {
    return GitFileChange(
      path: json['path'] as String? ?? '',
      status: json['status'] as String? ?? 'modified',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'status': status,
      };
}

class GitStatus {
  final String branch;
  final bool clean;
  final List<GitFileChange> staged;
  final List<GitFileChange> unstaged;
  final List<GitFileChange> untracked;

  const GitStatus({
    required this.branch,
    required this.clean,
    this.staged = const [],
    this.unstaged = const [],
    this.untracked = const [],
  });

  int get totalChanges => staged.length + unstaged.length + untracked.length;

  factory GitStatus.fromJson(Map<String, dynamic> json) {
    return GitStatus(
      branch: json['branch'] as String? ?? 'HEAD',
      clean: json['clean'] as bool? ?? true,
      staged: (json['staged'] as List<dynamic>?)
              ?.map((e) => GitFileChange.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      unstaged: (json['unstaged'] as List<dynamic>?)
              ?.map((e) => GitFileChange.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      untracked: (json['untracked'] as List<dynamic>?)
              ?.map((e) => GitFileChange.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'branch': branch,
        'clean': clean,
        'staged': staged.map((e) => e.toJson()).toList(),
        'unstaged': unstaged.map((e) => e.toJson()).toList(),
        'untracked': untracked.map((e) => e.toJson()).toList(),
      };
}

class ProjectInfo {
  final String name;
  final String path;
  final String kind;
  final String projectType;
  final GitStatus? git;

  const ProjectInfo({
    required this.name,
    required this.path,
    required this.kind,
    required this.projectType,
    this.git,
  });

  bool get isGit => kind == 'git';

  factory ProjectInfo.fromJson(Map<String, dynamic> json) {
    return ProjectInfo(
      name: json['name'] as String? ?? 'unnamed',
      path: json['path'] as String? ?? '',
      kind: json['kind'] as String? ?? 'directory',
      projectType: json['projectType'] as String? ?? 'generic',
      git: json['git'] != null
          ? GitStatus.fromJson(json['git'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'kind': kind,
        'projectType': projectType,
        if (git != null) 'git': git!.toJson(),
      };
}

class GitBranches {
  final String current;
  final List<String> local;
  final List<String> remote;

  const GitBranches({
    required this.current,
    this.local = const [],
    this.remote = const [],
  });

  factory GitBranches.fromJson(Map<String, dynamic> json) {
    return GitBranches(
      current: json['current'] as String? ?? '',
      local: (json['local'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      remote: (json['remote'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'current': current,
        'local': local,
        'remote': remote,
      };
}

class GitCommitResult {
  final String hash;
  final String branch;
  final String message;

  const GitCommitResult({
    required this.hash,
    required this.branch,
    required this.message,
  });

  factory GitCommitResult.fromJson(Map<String, dynamic> json) {
    return GitCommitResult(
      hash: json['hash'] as String? ?? '',
      branch: json['branch'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'branch': branch,
        'message': message,
      };
}

class GitCommit {
  final String hash;
  final String shortHash;
  final String message;
  final String author;
  final int timestamp;

  const GitCommit({
    required this.hash,
    required this.shortHash,
    required this.message,
    required this.author,
    required this.timestamp,
  });

  factory GitCommit.fromJson(Map<String, dynamic> json) {
    return GitCommit(
      hash: json['hash'] as String? ?? '',
      shortHash: json['shortHash'] as String? ?? '',
      message: json['message'] as String? ?? '',
      author: json['author'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'shortHash': shortHash,
        'message': message,
        'author': author,
        'timestamp': timestamp,
      };
}
