import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/orbit_websocket_client.dart';
import '../../../core/providers.dart';
import '../../../protocol/models/agent_status.dart';
import '../../../protocol/models/system_info.dart';
import '../../../core/storage/local_storage.dart';

class DashboardState {
  final bool isLoading;
  final AgentStatus? agentStatus;
  final SystemInfo? systemInfo;
  final String? errorMessage;
  final int? latencyMs;

  const DashboardState({
    this.isLoading = true,
    this.agentStatus,
    this.systemInfo,
    this.errorMessage,
    this.latencyMs,
  });

  DashboardState copyWith({
    bool? isLoading,
    AgentStatus? agentStatus,
    SystemInfo? systemInfo,
    String? errorMessage,
    int? latencyMs,
    bool clearError = false,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      agentStatus: agentStatus ?? this.agentStatus,
      systemInfo: systemInfo ?? this.systemInfo,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }
}

class DashboardController extends StateNotifier<DashboardState> {
  final OrbitWebSocketClient _client;
  final ILocalStorage? _storage;
  Timer? _refreshTimer;
  StreamSubscription? _stateSub;

  DashboardController(this._client, [this._storage]) : super(const DashboardState()) {
    refreshAll();
    _startAutoRefresh();
    // Refresh protected telemetry once the session becomes authenticated.
    // Transport connection alone (connectedUnpaired) is NOT sufficient:
    // agent.status / system.info require a paired session.
    _stateSub = _client.stateStream.listen((s) {
      if (s.isPaired) {
        refreshAll();
      }
    });
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_client.currentState.isPaired) {
        _fetchAgentStatusSilently();
      }
    });
  }

  Future<void> refreshAll() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await Future.wait([
      _fetchAgentStatus(),
      _fetchSystemInfo(),
    ]);
    state = state.copyWith(isLoading: false);
  }

  Future<void> _fetchAgentStatus() async {
    // Protected endpoint: only query after the session is authenticated.
    if (!_client.currentState.isPaired) return;
    try {
      final response = await _client.sendRequest('agent.status');
      if (response.success && response.payload != null) {
        state = state.copyWith(
          agentStatus: AgentStatus.fromJson(response.payload!),
          latencyMs: _client.currentState.latencyMs,
        );
      }
    } catch (_) {}
  }

  Future<void> _fetchAgentStatusSilently() async {
    // Protected endpoint: only query after the session is authenticated.
    if (!_client.currentState.isPaired) return;
    try {
      final response = await _client.sendRequest('agent.status');
      if (response.success && response.payload != null) {
        state = state.copyWith(
          agentStatus: AgentStatus.fromJson(response.payload!),
          latencyMs: _client.currentState.latencyMs,
        );
      }
    } catch (_) {}
  }

  Future<void> _fetchSystemInfo() async {
    // Protected endpoint: only query after the session is authenticated.
    if (!_client.currentState.isPaired) return;
    try {
      final response = await _client.sendRequest('system.info', payload: {'refresh': true});
      if (response.success && response.payload != null) {
        final sys = SystemInfo.fromJson(response.payload!);
        state = state.copyWith(
          systemInfo: sys,
        );

        final storage = _storage;
        if (storage != null) {
          try {
            final paired = await storage.getPairedDevice();
            if (paired != null) {
              final ts = sys.tailscale;
              final String? freshTs = (ts != null && ts.isConnected && ts.ip != null && ts.ip!.isNotEmpty)
                  ? ts.ip
                  : paired.tailscaleAddress;
              final String? freshState = ts?.state ?? paired.tailscaleState;
              final String freshName = sys.hostname.isNotEmpty ? sys.hostname : paired.pcDisplayName;

              if (freshTs != paired.tailscaleAddress ||
                  freshState != paired.tailscaleState ||
                  freshName != paired.pcDisplayName) {
                final updated = PairedDeviceRecord(
                  deviceId: paired.deviceId,
                  pcAddress: paired.pcAddress,
                  pcPort: paired.pcPort,
                  tailscaleAddress: freshTs,
                  pcDisplayName: freshName,
                  mobileDisplayName: paired.mobileDisplayName,
                  pairedAt: paired.pairedAt,
                  lastUsedPath: paired.lastUsedPath,
                  tailscaleState: freshState,
                );
                await storage.savePairedDevice(updated);
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}

final dashboardControllerProvider =
    StateNotifierProvider<DashboardController, DashboardState>((ref) {
  final client = ref.watch(webSocketClientProvider);
  ILocalStorage? storage;
  try {
    storage = ref.watch(localStorageProvider);
  } catch (_) {
    storage = null;
  }
  return DashboardController(client, storage);
});
