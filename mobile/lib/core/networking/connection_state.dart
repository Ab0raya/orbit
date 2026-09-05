enum OrbitConnectionStatus {
  disconnected,
  connecting,
  connectedUnpaired,
  pairing,
  paired,
  reconnecting,
  error;

  /// Backwards-compatible alias for connectedUnpaired
  static const connected = connectedUnpaired;
}

class OrbitConnectionState {
  final OrbitConnectionStatus status;
  final String? host;
  final int? port;
  final int? latencyMs;
  final String? errorMessage;
  final String? deviceId;

  const OrbitConnectionState({
    this.status = OrbitConnectionStatus.disconnected,
    this.host,
    this.port,
    this.latencyMs,
    this.errorMessage,
    this.deviceId,
  });

  OrbitConnectionState copyWith({
    OrbitConnectionStatus? status,
    String? host,
    int? port,
    int? latencyMs,
    String? errorMessage,
    String? deviceId,
  }) {
    return OrbitConnectionState(
      status: status ?? this.status,
      host: host ?? this.host,
      port: port ?? this.port,
      latencyMs: latencyMs ?? this.latencyMs,
      errorMessage: errorMessage ?? this.errorMessage,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  /// Returns true if transport socket is active (unpaired, pairing, or paired).
  bool get isConnected =>
      status == OrbitConnectionStatus.connectedUnpaired ||
      status == OrbitConnectionStatus.pairing ||
      status == OrbitConnectionStatus.paired;

  /// Returns true if WebSocket transport is established but pairing is not completed.
  bool get isUnpaired => status == OrbitConnectionStatus.connectedUnpaired;

  /// Returns true strictly when device is authenticated and paired.
  bool get isPaired => status == OrbitConnectionStatus.paired;
}

