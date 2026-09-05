class AgentStatus {
  final String status;
  final int uptimeSeconds;
  final String version;
  final int connectedDevices;

  const AgentStatus({
    required this.status,
    required this.uptimeSeconds,
    required this.version,
    required this.connectedDevices,
  });

  factory AgentStatus.fromJson(Map<String, dynamic> json) {
    return AgentStatus(
      status: json['status'] as String? ?? 'offline',
      uptimeSeconds: (json['uptimeSeconds'] as num?)?.toInt() ?? 0,
      version: json['version'] as String? ?? '0.1.0',
      connectedDevices: (json['connectedDevices'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'uptimeSeconds': uptimeSeconds,
        'version': version,
        'connectedDevices': connectedDevices,
      };

  String get formattedUptime {
    final hours = (uptimeSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((uptimeSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (uptimeSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
