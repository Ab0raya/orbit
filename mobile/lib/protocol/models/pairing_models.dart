class PairingPayload {
  final String code;
  final String name;
  final String platform;
  final String? deviceId;

  const PairingPayload({
    required this.code,
    required this.name,
    required this.platform,
    this.deviceId,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'platform': platform,
        if (deviceId != null && deviceId!.isNotEmpty) 'deviceId': deviceId,
      };
}

class PairingResult {
  final bool paired;
  final String deviceId;

  const PairingResult({
    required this.paired,
    required this.deviceId,
  });

  factory PairingResult.fromJson(Map<String, dynamic> json) {
    return PairingResult(
      paired: json['paired'] as bool? ?? false,
      deviceId: json['deviceId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'paired': paired,
        'deviceId': deviceId,
      };
}

class OrbitPairingQrPayload {
  final String host;
  final int port;
  final String code;
  final int? expires;
  final String? tailscaleHost;
  final String version;

  const OrbitPairingQrPayload({
    required this.host,
    required this.port,
    required this.code,
    this.expires,
    this.tailscaleHost,
    this.version = 'v1',
  });

  bool get isExpired {
    if (expires == null) return false;
    // Normalize second (~10 digits) vs millisecond (~13 digits) timestamps
    final expMs = expires! < 10000000000 ? expires! * 1000 : expires!;
    return DateTime.now().millisecondsSinceEpoch > expMs;
  }

  static OrbitPairingQrPayload? tryParse(String raw) {
    try {
      return parse(raw);
    } catch (_) {
      return null;
    }
  }

  static OrbitPairingQrPayload parse(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('orbit://')) {
      throw const FormatException('Invalid URI scheme. Must start with orbit://');
    }

    final uri = Uri.parse(trimmed);
    if (uri.scheme != 'orbit') {
      throw const FormatException('Invalid URI scheme');
    }

    // Host or path can carry "pair" e.g. orbit://pair or orbit://pair/v1
    final isPairPath = uri.host == 'pair' || uri.path.contains('pair');
    if (!isPairPath) {
      throw const FormatException('Invalid Orbit pairing QR: not a pairing endpoint');
    }

    final queryParams = uri.queryParameters;
    final host = queryParams['host']?.trim();
    if (host == null || host.isEmpty || host.contains(' ')) {
      throw const FormatException('Missing or invalid host parameter in pairing QR');
    }

    final portStr = queryParams['port'];
    final port = int.tryParse(portStr ?? '');
    if (port == null || port < 1 || port > 65535) {
      throw const FormatException('Missing or invalid port in pairing QR (must be 1-65535)');
    }

    final code = queryParams['code']?.trim();
    if (code == null || code.length != 6 || int.tryParse(code) == null) {
      throw const FormatException('Missing or invalid 6-digit pairing code in QR');
    }

    int? expires;
    if (queryParams.containsKey('expires')) {
      expires = int.tryParse(queryParams['expires']!);
    }

    final tsHost = queryParams['ts_host']?.trim() ??
        queryParams['tailscale_host']?.trim() ??
        queryParams['tsHost']?.trim();

    var version = 'v1';
    if (uri.path.contains('v1') || queryParams['version'] == '1') {
      version = 'v1';
    }

    return OrbitPairingQrPayload(
      host: host,
      port: port,
      code: code,
      expires: expires,
      tailscaleHost: tsHost != null && tsHost.isNotEmpty ? tsHost : null,
      version: version,
    );
  }

  String toUriString() {
    final expiresParam = expires != null ? '&expires=$expires' : '';
    final tsParam = tailscaleHost != null && tailscaleHost!.isNotEmpty
        ? '&ts_host=$tailscaleHost'
        : '';
    return 'orbit://pair/$version?host=$host&port=$port&code=$code$expiresParam$tsParam';
  }
}
