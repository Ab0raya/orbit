class FileRoot {
  final String name;
  final String path;
  final String? label;
  final String? kind;
  final bool isRemovable;

  const FileRoot({
    required this.name,
    required this.path,
    this.label,
    this.kind,
    this.isRemovable = false,
  });

  factory FileRoot.fromJson(Map<String, dynamic> json) {
    return FileRoot(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      label: json['label'] as String?,
      kind: json['kind'] as String?,
      isRemovable: json['isRemovable'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        if (label != null) 'label': label,
        if (kind != null) 'kind': kind,
        'isRemovable': isRemovable,
      };
}

class FileEntry {
  final String name;
  final String path;
  final String kind; // 'file' | 'directory'
  final int size;
  final int? modifiedAt;
  final bool hidden;

  const FileEntry({
    required this.name,
    required this.path,
    required this.kind,
    required this.size,
    this.modifiedAt,
    required this.hidden,
  });

  bool get isDirectory => kind == 'directory';
  bool get isFile => kind == 'file';

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      kind: json['kind'] as String? ?? 'file',
      size: (json['size'] as num?)?.toInt() ?? 0,
      modifiedAt: (json['modifiedAt'] as num?)?.toInt(),
      hidden: json['hidden'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'kind': kind,
        'size': size,
        'modifiedAt': modifiedAt,
        'hidden': hidden,
      };

  String get formattedSize {
    if (isDirectory) return 'Folder';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class FileListResponse {
  final String path;
  final List<FileEntry> entries;

  const FileListResponse({
    required this.path,
    required this.entries,
  });

  factory FileListResponse.fromJson(Map<String, dynamic> json) {
    final entriesRaw = json['entries'] as List<dynamic>? ?? [];
    return FileListResponse(
      path: json['path'] as String? ?? '',
      entries: entriesRaw
          .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'entries': entries.map((e) => e.toJson()).toList(),
      };
}

class FileReadResponse {
  final String path;
  final String content;
  final String encoding;
  final int size;

  const FileReadResponse({
    required this.path,
    required this.content,
    required this.encoding,
    required this.size,
  });

  factory FileReadResponse.fromJson(Map<String, dynamic> json) {
    return FileReadResponse(
      path: json['path'] as String? ?? '',
      content: json['content'] as String? ?? '',
      encoding: json['encoding'] as String? ?? 'utf8',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'content': content,
        'encoding': encoding,
        'size': size,
      };
}

class FileWriteResponse {
  final String path;
  final int size;
  final bool success;

  const FileWriteResponse({
    required this.path,
    required this.size,
    required this.success,
  });

  factory FileWriteResponse.fromJson(Map<String, dynamic> json) {
    return FileWriteResponse(
      path: json['path'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      success: json['success'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'size': size,
        'success': success,
      };
}

enum FileCategory {
  markdown,
  text,
  code,
  image,
  binary;

  static FileCategory fromString(String str) {
    return FileCategory.values.firstWhere(
      (c) => c.name.toLowerCase() == str.toLowerCase(),
      orElse: () => FileCategory.binary,
    );
  }

  static FileCategory fromExtension(String extOrPath) {
    var ext = extOrPath.toLowerCase();
    if (ext.contains('.')) {
      ext = ext.split('.').last;
    }
    const markdowns = {'md', 'markdown', 'mdx'};
    const images = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'};
    const codes = {
      'dart', 'ts', 'tsx', 'js', 'jsx', 'rs', 'py', 'java', 'kotlin', 'kt',
      'swift', 'c', 'cpp', 'h', 'hpp', 'go', 'php', 'rb', 'sh', 'bash', 'zsh',
      'css', 'scss', 'html', 'htm', 'vue', 'svelte', 'sql', 'toml'
    };
    const texts = {
      'txt', 'log', 'yaml', 'yml', 'json', 'xml', 'csv', 'env', 'ini', 'conf'
    };

    if (markdowns.contains(ext)) return FileCategory.markdown;
    if (images.contains(ext)) return FileCategory.image;
    if (codes.contains(ext)) return FileCategory.code;
    if (texts.contains(ext)) return FileCategory.text;
    return FileCategory.binary;
  }
}

class SearchFileResult {
  final String path;
  final String name;
  final bool isDirectory;
  final int? line;
  final String? snippet;

  const SearchFileResult({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.line,
    this.snippet,
  });

  factory SearchFileResult.fromJson(Map<String, dynamic> json) {
    return SearchFileResult(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isDirectory: json['isDirectory'] as bool? ?? json['is_directory'] as bool? ?? false,
      line: (json['lineNumber'] as num?)?.toInt() ?? (json['line'] as num?)?.toInt(),
      snippet: json['lineContent'] as String? ?? json['snippet'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'isDirectory': isDirectory,
        if (line != null) 'line': line,
        if (line != null) 'lineNumber': line,
        if (snippet != null) 'snippet': snippet,
        if (snippet != null) 'lineContent': snippet,
      };
}

class FileSearchResult {
  final String root;
  final String query;
  final String mode; // 'name' | 'content'
  final int totalMatches;
  final bool truncated;
  final List<SearchFileResult> results;

  const FileSearchResult({
    required this.root,
    required this.query,
    required this.mode,
    required this.totalMatches,
    required this.truncated,
    required this.results,
  });

  factory FileSearchResult.fromJson(Map<String, dynamic> json) {
    final resultsRaw = json['results'] as List<dynamic>? ?? [];
    return FileSearchResult(
      root: json['root'] as String? ?? '',
      query: json['query'] as String? ?? '',
      mode: json['mode'] as String? ?? 'name',
      totalMatches: (json['totalMatches'] as num?)?.toInt() ?? 0,
      truncated: json['truncated'] as bool? ?? false,
      results: resultsRaw
          .map((r) => SearchFileResult.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'root': root,
        'query': query,
        'mode': mode,
        'totalMatches': totalMatches,
        'truncated': truncated,
        'results': results.map((r) => r.toJson()).toList(),
      };
}

class BinaryReadResponse {
  final String path;
  final String name;
  final String extension;
  final int size;
  final String mimeType;
  final FileCategory fileCategory;
  final String encoding;
  final String? content;
  final int? width;
  final int? height;
  final int? modifiedAt;
  final bool isTooLarge;

  const BinaryReadResponse({
    required this.path,
    required this.name,
    required this.extension,
    required this.size,
    required this.mimeType,
    required this.fileCategory,
    required this.encoding,
    this.content,
    this.width,
    this.height,
    this.modifiedAt,
    this.isTooLarge = false,
  });

  factory BinaryReadResponse.fromJson(Map<String, dynamic> json) {
    final catStr = json['fileCategory'] as String? ?? 'binary';
    return BinaryReadResponse(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      extension: json['extension'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      fileCategory: FileCategory.fromString(catStr),
      encoding: json['encoding'] as String? ?? 'base64',
      content: json['content'] as String?,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      modifiedAt: (json['modifiedAt'] as num?)?.toInt(),
      isTooLarge: json['isTooLarge'] as bool? ?? false,
    );
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get dimensionsText {
    if (width != null && height != null) {
      return '$width × $height';
    }
    return '';
  }
}
