class PairedDeviceRecord {
  final String deviceId;
  final String pcAddress;
  final int pcPort;
  final String? tailscaleAddress;
  final String pcDisplayName;
  final String mobileDisplayName;
  final int pairedAt;
  final String? lastUsedPath;
  final String? tailscaleState;

  const PairedDeviceRecord({
    required this.deviceId,
    required this.pcAddress,
    required this.pcPort,
    this.tailscaleAddress,
    required this.pcDisplayName,
    required this.mobileDisplayName,
    required this.pairedAt,
    this.lastUsedPath,
    this.tailscaleState,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'pcAddress': pcAddress,
        'pcPort': pcPort,
        if (tailscaleAddress != null) 'tailscaleAddress': tailscaleAddress,
        'pcDisplayName': pcDisplayName,
        'mobileDisplayName': mobileDisplayName,
        'pairedAt': pairedAt,
        if (lastUsedPath != null) 'lastUsedPath': lastUsedPath,
        if (tailscaleState != null) 'tailscaleState': tailscaleState,
      };

  factory PairedDeviceRecord.fromJson(Map<String, dynamic> json) {
    return PairedDeviceRecord(
      deviceId: json['deviceId'] as String? ?? '',
      pcAddress: json['pcAddress'] as String? ?? '127.0.0.1',
      pcPort: (json['pcPort'] as num?)?.toInt() ?? 4371,
      tailscaleAddress: json['tailscaleAddress'] as String?,
      pcDisplayName: json['pcDisplayName'] as String? ?? 'My PC',
      mobileDisplayName: json['mobileDisplayName'] as String? ?? 'Orbit Mobile',
      pairedAt: (json['pairedAt'] as num?)?.toInt() ?? 0,
      lastUsedPath: json['lastUsedPath'] as String?,
      tailscaleState: json['tailscaleState'] as String?,
    );
  }
}

abstract class ILocalStorage {
  Future<void> savePairedDevice(PairedDeviceRecord record);
  Future<PairedDeviceRecord?> getPairedDevice();
  Future<void> clearPairedDevice();

  Future<void> saveRecentConnection(String host, int port);
  Future<Map<String, dynamic>?> getRecentConnection();

  Future<String> getOrCreateInstallationDeviceId();

  Future<void> saveShowHiddenFiles(bool show);
  Future<bool> getShowHiddenFiles();
}
