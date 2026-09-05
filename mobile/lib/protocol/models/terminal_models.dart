class TerminalSessionSummary {
  final String sessionId;
  final String status;
  final String cwd;
  final String shell;
  final int rows;
  final int cols;
  final int createdAt;
  final int lastActivityAt;
  final int? exitCode;
  final String ownerDeviceId;

  const TerminalSessionSummary({
    required this.sessionId,
    required this.status,
    required this.cwd,
    required this.shell,
    required this.rows,
    required this.cols,
    required this.createdAt,
    required this.lastActivityAt,
    this.exitCode,
    required this.ownerDeviceId,
  });

  factory TerminalSessionSummary.fromJson(Map<String, dynamic> json) {
    return TerminalSessionSummary(
      sessionId: json['sessionId'] as String? ?? '',
      status: json['status'] as String? ?? 'starting',
      cwd: json['cwd'] as String? ?? '',
      shell: json['shell'] as String? ?? '',
      rows: (json['rows'] as num?)?.toInt() ?? 30,
      cols: (json['cols'] as num?)?.toInt() ?? 120,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      lastActivityAt: (json['lastActivityAt'] as num?)?.toInt() ?? 0,
      exitCode: (json['exitCode'] as num?)?.toInt(),
      ownerDeviceId: json['ownerDeviceId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'status': status,
        'cwd': cwd,
        'shell': shell,
        'rows': rows,
        'cols': cols,
        'createdAt': createdAt,
        'lastActivityAt': lastActivityAt,
        if (exitCode != null) 'exitCode': exitCode,
        'ownerDeviceId': ownerDeviceId,
      };

  bool get isRunning => status == 'running';
  bool get isExited => status == 'exited' || status == 'killed';
}

class TerminalCreatePayload {
  final String? cwd;
  final int? cols;
  final int? rows;

  const TerminalCreatePayload({this.cwd, this.cols, this.rows});

  Map<String, dynamic> toJson() => {
        if (cwd != null) 'cwd': cwd,
        if (cols != null) 'cols': cols,
        if (rows != null) 'rows': rows,
      };
}

class TerminalInputPayload {
  final String sessionId;
  final String data;

  const TerminalInputPayload({
    required this.sessionId,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'data': data,
      };
}

class TerminalResizePayload {
  final String sessionId;
  final int cols;
  final int rows;

  const TerminalResizePayload({
    required this.sessionId,
    required this.cols,
    required this.rows,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'cols': cols,
        'rows': rows,
      };
}

class TerminalKillPayload {
  final String sessionId;

  const TerminalKillPayload({required this.sessionId});

  Map<String, dynamic> toJson() => {'sessionId': sessionId};
}

class TerminalHistoryPayload {
  final String sessionId;

  const TerminalHistoryPayload({required this.sessionId});

  Map<String, dynamic> toJson() => {'sessionId': sessionId};
}
