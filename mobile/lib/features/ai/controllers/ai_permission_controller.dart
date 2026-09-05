import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/connection_state.dart';
import '../../../core/networking/orbit_websocket_client.dart';
import '../../../core/providers.dart';
import '../models/ai_permission_models.dart';

class AiPermissionStateHolder {
  final List<AiPermissionRequest> pendingRequests;
  final bool isLoading;
  final String? errorMessage;

  const AiPermissionStateHolder({
    this.pendingRequests = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  AiPermissionStateHolder copyWith({
    List<AiPermissionRequest>? pendingRequests,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AiPermissionStateHolder(
      pendingRequests: pendingRequests ?? this.pendingRequests,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AiPermissionController extends StateNotifier<AiPermissionStateHolder> {
  final OrbitWebSocketClient _client;
  StreamSubscription? _eventSub;
  StreamSubscription? _stateSub;

  AiPermissionController(this._client) : super(const AiPermissionStateHolder()) {
    _init();
  }

  void _init() {
    // 1. Listen for WebSocket events
    _eventSub = _client.events.listen((event) {
      if (event.event == 'ai.permission.requested') {
        _handlePermissionRequested(event.payload);
      } else if (event.event == 'ai.permission.resolved') {
        _handlePermissionResolved(event.payload);
      }
    });

    // 2. Listen for connection state changes to restore permissions upon reconnect
    _stateSub = _client.stateStream.listen((connState) {
      if (connState.status == OrbitConnectionStatus.paired) {
        restorePermissions();
      }
    });

    // Initial check if already connected & paired
    if (_client.currentState.status == OrbitConnectionStatus.paired) {
      restorePermissions();
    }
  }

  void _handlePermissionRequested(Map<String, dynamic> payload) {
    try {
      final req = AiPermissionRequest.fromJson(payload);
      final list = List<AiPermissionRequest>.from(state.pendingRequests);
      final idx = list.indexWhere((p) => p.permissionId == req.permissionId);
      if (idx >= 0) {
        list[idx] = req;
      } else {
        list.add(req);
      }
      state = state.copyWith(pendingRequests: list, clearError: true);
    } catch (e) {
      // Ignore or log malformed payload
    }
  }

  void _handlePermissionResolved(Map<String, dynamic> payload) {
    final permissionId = payload['permissionId'] as String? ?? payload['id'] as String?;
    if (permissionId != null) {
      removeRequest(permissionId);
    }
  }

  void removeRequest(String permissionId) {
    final list = state.pendingRequests.where((p) => p.permissionId != permissionId).toList();
    state = state.copyWith(pendingRequests: list);
  }

  Future<void> restorePermissions() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _client.sendRequest('ai.permission.list');
      if (res.success && res.payload != null) {
        final requestsRaw = res.payload!['permissions'] as List<dynamic>? ??
            res.payload!['requests'] as List<dynamic>? ??
            [];
        final requests = requestsRaw
            .map((r) => AiPermissionRequest.fromJson(r as Map<String, dynamic>))
            .where((r) => r.isPending)
            .toList();
        state = state.copyWith(pendingRequests: requests, isLoading: false);
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<bool> resolvePermission(String permissionId, String decision) async {
    state = state.copyWith(clearError: true);
    try {
      final res = await _client.sendRequest('ai.permission.resolve', payload: {
        'permissionId': permissionId,
        'decision': decision,
      });

      if (res.success) {
        removeRequest(permissionId);
        return true;
      } else {
        state = state.copyWith(
          errorMessage: res.error?.message ?? 'Failed to resolve permission',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  List<AiPermissionRequest> pendingRequestsForTask(String taskId) {
    return state.pendingRequests.where((p) => p.taskId == taskId).toList();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}

final aiPermissionControllerProvider = StateNotifierProvider<
    AiPermissionController, AiPermissionStateHolder>((ref) {
  final client = ref.watch(webSocketClientProvider);
  return AiPermissionController(client);
});
