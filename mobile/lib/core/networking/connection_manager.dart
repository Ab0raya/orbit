import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'orbit_websocket_client.dart';
import 'connection_state.dart';
import '../storage/local_storage.dart';
import '../providers.dart';
import '../../protocol/models/system_info.dart';

enum ConnectionPathType {
  localLan,
  tailscale;

  String get label {
    switch (this) {
      case ConnectionPathType.localLan:
        return 'Local Network';
      case ConnectionPathType.tailscale:
        return 'Tailscale';
    }
  }
}

enum TailscaleEnvironmentStatus {
  ready,
  setupRequired,
  unavailable;

  String get label {
    switch (this) {
      case TailscaleEnvironmentStatus.ready:
        return 'Ready';
      case TailscaleEnvironmentStatus.setupRequired:
        return 'Setup required';
      case TailscaleEnvironmentStatus.unavailable:
        return 'Unavailable';
    }
  }
}

class ConnectionManagerState {
  final ConnectionPathType? activePath;
  final ConnectionPathType? preferredPath;
  final String? lanHost;
  final String? tsHost;
  final int port;
  final bool isSwitching;
  final String? lastError;

  const ConnectionManagerState({
    this.activePath,
    this.preferredPath,
    this.lanHost,
    this.tsHost,
    this.port = 4371,
    this.isSwitching = false,
    this.lastError,
  });

  ConnectionManagerState copyWith({
    ConnectionPathType? activePath,
    ConnectionPathType? preferredPath,
    String? lanHost,
    String? tsHost,
    int? port,
    bool? isSwitching,
    String? lastError,
    bool clearActivePath = false,
    bool clearError = false,
  }) {
    return ConnectionManagerState(
      activePath: clearActivePath ? null : (activePath ?? this.activePath),
      preferredPath: preferredPath ?? this.preferredPath,
      lanHost: lanHost ?? this.lanHost,
      tsHost: tsHost ?? this.tsHost,
      port: port ?? this.port,
      isSwitching: isSwitching ?? this.isSwitching,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  bool get hasTailscale => tsHost != null && tsHost!.isNotEmpty;
  bool get hasLan => lanHost != null && lanHost!.isNotEmpty;
}

class ConnectionManager extends StateNotifier<ConnectionManagerState> {
  final OrbitWebSocketClient _client;
  final ILocalStorage _storage;
  StreamSubscription? _stateSub;

  ConnectionManager(this._client, this._storage)
      : super(const ConnectionManagerState()) {
    _initFromStorage();
    _listenToClientState();
  }

  Future<void> _initFromStorage() async {
    final paired = await _storage.getPairedDevice();
    if (paired != null) {
      ConnectionPathType? lastPath;
      if (paired.lastUsedPath == 'tailscale') {
        lastPath = ConnectionPathType.tailscale;
      } else if (paired.lastUsedPath == 'localLan') {
        lastPath = ConnectionPathType.localLan;
      }

      state = state.copyWith(
        lanHost: paired.pcAddress,
        tsHost: paired.tailscaleAddress,
        port: paired.pcPort,
        preferredPath: lastPath,
      );
    }
  }

  void _listenToClientState() {
    _stateSub = _client.stateStream.listen((connState) {
      if (connState.status == OrbitConnectionStatus.disconnected ||
          connState.status == OrbitConnectionStatus.error) {
        if (state.activePath != null && !state.isSwitching) {
          state = state.copyWith(clearActivePath: true);
        }
      }
    });
  }

  void setEndpoints({
    String? lanHost,
    String? tsHost,
    int? port,
  }) {
    state = state.copyWith(
      lanHost: lanHost?.trim(),
      tsHost: tsHost?.trim(),
      port: port,
      clearError: true,
    );
  }

  void setPreferredPath(ConnectionPathType? path) {
    state = state.copyWith(preferredPath: path);
  }

  /// Attempts to connect preferring Local LAN first if reachable, falling back to Tailscale.
  /// If user selected a preference (or explicit path), that path is tried first.
  Future<bool> connectOptimal({
    String? lanHost,
    String? tsHost,
    int? port,
  }) async {
    final effectiveLan = lanHost ?? state.lanHost;
    final effectiveTs = tsHost ?? state.tsHost;
    final effectivePort = port ?? state.port;

    state = state.copyWith(
      lanHost: effectiveLan,
      tsHost: effectiveTs,
      port: effectivePort,
      isSwitching: true,
      clearError: true,
    );

    // If preferred is Tailscale and tsHost is present, try Tailscale first
    if (state.preferredPath == ConnectionPathType.tailscale &&
        effectiveTs != null &&
        effectiveTs.isNotEmpty) {
      final success = await _tryConnect(effectiveTs, effectivePort, ConnectionPathType.tailscale);
      if (success) {
        state = state.copyWith(isSwitching: false);
        return true;
      }
      // Tailscale failed, fall back to LAN if available
      if (effectiveLan != null && effectiveLan.isNotEmpty) {
        final lanOk = await _tryConnect(effectiveLan, effectivePort, ConnectionPathType.localLan);
        state = state.copyWith(isSwitching: false);
        return lanOk;
      }
      state = state.copyWith(isSwitching: false, lastError: 'Could not connect via Tailscale or LAN');
      return false;
    }

    // Default: Prefer Local LAN first if available
    if (effectiveLan != null && effectiveLan.isNotEmpty) {
      final lanSuccess = await _tryConnect(effectiveLan, effectivePort, ConnectionPathType.localLan);
      if (lanSuccess) {
        state = state.copyWith(isSwitching: false);
        return true;
      }
    }

    // Fallback to Tailscale
    if (effectiveTs != null && effectiveTs.isNotEmpty) {
      final tsSuccess = await _tryConnect(effectiveTs, effectivePort, ConnectionPathType.tailscale);
      if (tsSuccess) {
        state = state.copyWith(isSwitching: false);
        return true;
      }
    }

    state = state.copyWith(
      isSwitching: false,
      lastError: 'Failed to connect via Local LAN or Tailscale',
    );
    return false;
  }

  /// Switch cleanly to a specific connection path.
  Future<bool> switchPath(ConnectionPathType targetPath) async {
    final host = targetPath == ConnectionPathType.tailscale ? state.tsHost : state.lanHost;
    if (host == null || host.isEmpty) {
      state = state.copyWith(lastError: '${targetPath.label} address not configured');
      return false;
    }

    // If already connected on that path, keep it
    if (state.activePath == targetPath && _client.currentState.isConnected) {
      return true;
    }

    state = state.copyWith(isSwitching: true, clearError: true);

    try {
      _client.disconnect();
      final success = await _tryConnect(host, state.port, targetPath);
      state = state.copyWith(
        isSwitching: false,
        preferredPath: targetPath,
      );
      return success;
    } catch (e) {
      state = state.copyWith(
        isSwitching: false,
        lastError: 'Failed to switch to ${targetPath.label}: $e',
      );
      return false;
    }
  }

  Future<bool> _tryConnect(String host, int port, ConnectionPathType pathType) async {
    try {
      await _client.connect(host, port);
      await _client.sendPing();

      // Attempt session resume with stable installation identity
      final installationId = await _storage.getOrCreateInstallationDeviceId();
      final pairedRecord = await _storage.getPairedDevice();
      String? discoveredTsHost = state.tsHost;
      String? discoveredTsState = pairedRecord?.tailscaleState;
      String? discoveredPcName = pairedRecord?.pcDisplayName;

      if (pairedRecord != null) {
        try {
          final resumeRes = await _client.sendRequest(
            'session.resume',
            payload: {'deviceId': installationId},
          );
          if (resumeRes.success && resumeRes.payload?['resumed'] == true) {
            _client.markPaired(installationId);

            // Query system.info to enrich Tailscale endpoint
            try {
              final sysRes = await _client.sendRequest(
                'system.info',
                payload: {'refresh': true},
                timeout: const Duration(milliseconds: 3000),
              );
              if (sysRes.success && sysRes.payload != null) {
                final sys = SystemInfo.fromJson(sysRes.payload!);
                final ts = sys.tailscale;
                if (ts != null && ts.isConnected && ts.ip != null && ts.ip!.isNotEmpty) {
                  discoveredTsHost = ts.ip;
                }
                discoveredTsState = ts?.state ?? discoveredTsState;
                if (sys.hostname.isNotEmpty) {
                  discoveredPcName = sys.hostname;
                }
              }
            } catch (_) {}
          }
        } catch (_) {
          // Resume failed or not yet paired on this session
        }
      }

      state = state.copyWith(
        activePath: pathType,
        tsHost: discoveredTsHost ?? state.tsHost,
      );

      // Save updated paired device record to storage
      if (pairedRecord != null) {
        final updated = PairedDeviceRecord(
          deviceId: pairedRecord.deviceId,
          pcAddress: pairedRecord.pcAddress,
          pcPort: pairedRecord.pcPort,
          tailscaleAddress: discoveredTsHost ?? pairedRecord.tailscaleAddress,
          pcDisplayName: discoveredPcName ?? pairedRecord.pcDisplayName,
          mobileDisplayName: pairedRecord.mobileDisplayName,
          pairedAt: pairedRecord.pairedAt,
          lastUsedPath: pathType.name,
          tailscaleState: discoveredTsState,
        );
        await _storage.savePairedDevice(updated);
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }
}

final connectionManagerProvider =
    StateNotifierProvider<ConnectionManager, ConnectionManagerState>((ref) {
  final client = ref.watch(webSocketClientProvider);
  final storage = ref.watch(localStorageProvider);
  return ConnectionManager(client, storage);
});
