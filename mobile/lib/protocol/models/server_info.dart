class ServerInfo {
  final int port;
  final bool isListening;
  final String bindAddress;
  final int connectedClients;

  const ServerInfo({
    required this.port,
    required this.isListening,
    required this.bindAddress,
    required this.connectedClients,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      port: (json['port'] as num?)?.toInt() ?? 4371,
      isListening: json['isListening'] as bool? ?? false,
      bindAddress: json['bindAddress'] as String? ?? '0.0.0.0',
      connectedClients: (json['connectedClients'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'port': port,
        'isListening': isListening,
        'bindAddress': bindAddress,
        'connectedClients': connectedClients,
      };
}
