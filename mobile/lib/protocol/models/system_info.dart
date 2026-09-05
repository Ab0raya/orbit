class TailscaleInfoModel {
  final bool installed;
  final bool running;
  final String state; // "not_installed" | "needs_login" | "stopped" | "connected"
  final String? ip;
  final String? deviceName;
  final String? tailnetName;
  final String? error;

  const TailscaleInfoModel({
    required this.installed,
    required this.running,
    required this.state,
    this.ip,
    this.deviceName,
    this.tailnetName,
    this.error,
  });

  bool get isConnected => state == 'connected' && ip != null && ip!.isNotEmpty;
  bool get isReady => isConnected;
  bool get isSetupRequired => installed && !isConnected;
  bool get isUnavailable => !installed || state == 'not_installed';

  factory TailscaleInfoModel.fromJson(Map<String, dynamic> json) {
    return TailscaleInfoModel(
      installed: json['installed'] as bool? ?? false,
      running: json['running'] as bool? ?? false,
      state: json['state'] as String? ?? 'not_installed',
      ip: json['ip'] as String?,
      deviceName: (json['device_name'] ?? json['deviceName']) as String?,
      tailnetName: (json['tailnet_name'] ?? json['tailnetName'] ?? json['tailnet']) as String?,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'installed': installed,
        'running': running,
        'state': state,
        if (ip != null) 'ip': ip,
        if (deviceName != null) 'device_name': deviceName,
        if (tailnetName != null) 'tailnet_name': tailnetName,
        if (error != null) 'error': error,
      };
}

class NetworkAdapterInfo {
  final String interfaceName;
  final String ip;
  final bool isIpv4;
  final bool isLoopback;

  const NetworkAdapterInfo({
    required this.interfaceName,
    required this.ip,
    required this.isIpv4,
    required this.isLoopback,
  });

  factory NetworkAdapterInfo.fromJson(Map<String, dynamic> json) {
    return NetworkAdapterInfo(
      interfaceName: (json['interface_name'] ?? json['interfaceName']) as String? ?? 'eth0',
      ip: json['ip'] as String? ?? '127.0.0.1',
      isIpv4: (json['is_ipv4'] ?? json['isIpv4']) as bool? ?? true,
      isLoopback: (json['is_loopback'] ?? json['isLoopback']) as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'interface_name': interfaceName,
        'ip': ip,
        'is_ipv4': isIpv4,
        'is_loopback': isLoopback,
      };
}

class SystemInfo {
  final String hostname;
  final String os;
  final String osVersion;
  final String architecture;
  final String? primaryIp;
  final List<NetworkAdapterInfo> network;
  final TailscaleInfoModel? tailscale;

  const SystemInfo({
    required this.hostname,
    required this.os,
    required this.osVersion,
    required this.architecture,
    this.primaryIp,
    this.network = const [],
    this.tailscale,
  });

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    final netList = ((json['local_ips'] ?? json['network']) as List<dynamic>?)
            ?.map((e) => NetworkAdapterInfo.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final tsJson = json['tailscale'] as Map<String, dynamic>?;
    final tailscale = tsJson != null ? TailscaleInfoModel.fromJson(tsJson) : null;

    return SystemInfo(
      hostname: (json['device_name'] ?? json['hostname']) as String? ?? 'Unknown Host',
      os: json['os'] as String? ?? 'Linux',
      osVersion: (json['os_version'] ?? json['osVersion']) as String? ?? '',
      architecture: (json['arch'] ?? json['architecture']) as String? ?? 'x86_64',
      primaryIp: (json['primary_ip'] ?? json['primaryIp']) as String?,
      network: netList,
      tailscale: tailscale,
    );
  }

  Map<String, dynamic> toJson() => {
        'hostname': hostname,
        'os': os,
        'osVersion': osVersion,
        'architecture': architecture,
        if (primaryIp != null) 'primaryIp': primaryIp,
        'network': network.map((e) => e.toJson()).toList(),
        if (tailscale != null) 'tailscale': tailscale!.toJson(),
      };
}
