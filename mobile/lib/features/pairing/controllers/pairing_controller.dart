import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/orbit_websocket_client.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/providers.dart';
import '../../../protocol/models/pairing_models.dart';
import '../../../protocol/models/system_info.dart';

class PairingScreenState {
  final String code;
  final bool isPairing;
  final String? errorMessage;
  final bool isSuccess;

  const PairingScreenState({
    this.code = '',
    this.isPairing = false,
    this.errorMessage,
    this.isSuccess = false,
  });

  PairingScreenState copyWith({
    String? code,
    bool? isPairing,
    String? errorMessage,
    bool? isSuccess,
    bool clearError = false,
  }) {
    return PairingScreenState(
      code: code ?? this.code,
      isPairing: isPairing ?? this.isPairing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }
}

class PairingController extends StateNotifier<PairingScreenState> {
  final OrbitWebSocketClient _client;
  final ILocalStorage _storage;

  PairingController(this._client, this._storage)
      : super(const PairingScreenState());

  void setCode(String code) {
    state = state.copyWith(code: code.trim(), clearError: true);
  }

  Future<bool> verifyPairing(String host, int port) async {
    final code = state.code.replaceAll(RegExp(r'\s+'), '');
    if (code.length != 6) {
      state = state.copyWith(errorMessage: 'Please enter a 6-digit code');
      return false;
    }

    state = state.copyWith(isPairing: true, clearError: true);
    _client.markPairing();

    try {
      final platform = Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'linux');
      final deviceName = Platform.isIOS ? 'iPhone' : (Platform.isAndroid ? 'Android Phone' : 'Linux Client');
      final installationDeviceId = await _storage.getOrCreateInstallationDeviceId();

      final payload = PairingPayload(
        code: code,
        name: deviceName,
        platform: platform,
        deviceId: installationDeviceId,
      );

      final response = await _client.sendRequest(
        'pairing.verify',
        payload: payload.toJson(),
      );

      if (!response.success) {
        _client.markUnpaired();
        state = state.copyWith(
          isPairing: false,
          errorMessage: response.error?.message ?? 'Pairing verification failed',
        );
        return false;
      }

      final result = PairingResult.fromJson(response.payload ?? {});
      if (!result.paired || result.deviceId.isEmpty) {
        _client.markUnpaired();
        state = state.copyWith(
          isPairing: false,
          errorMessage: 'Pairing failed: Invalid response from PC',
        );
        return false;
      }

      _client.markPaired(result.deviceId);

      // Query authoritative system.info immediately after pairing
      String? tsAddress;
      String? tsState;
      String pcName = 'Developer PC ($host)';
      try {
        final sysRes = await _client.sendRequest('system.info', payload: {'refresh': true});
        if (sysRes.success && sysRes.payload != null) {
          final sys = SystemInfo.fromJson(sysRes.payload!);
          if (sys.hostname.isNotEmpty) {
            pcName = sys.hostname;
          }
          final ts = sys.tailscale;
          if (ts != null) {
            tsState = ts.state;
            if (ts.isConnected && ts.ip != null && ts.ip!.isNotEmpty) {
              tsAddress = ts.ip;
            }
          }
        }
      } catch (_) {
        // Fallback to basic record if system.info request fails
      }

      // Save enriched paired device record
      final record = PairedDeviceRecord(
        deviceId: result.deviceId,
        pcAddress: host,
        pcPort: port,
        tailscaleAddress: tsAddress,
        pcDisplayName: pcName,
        mobileDisplayName: deviceName,
        pairedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        tailscaleState: tsState,
      );
      await _storage.savePairedDevice(record);

      state = state.copyWith(isPairing: false, isSuccess: true);
      return true;
    } catch (e) {
      _client.markUnpaired();
      state = state.copyWith(
        isPairing: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }
}

final pairingControllerProvider =
    StateNotifierProvider<PairingController, PairingScreenState>((ref) {
  final client = ref.watch(webSocketClientProvider);
  final storage = ref.watch(localStorageProvider);
  return PairingController(client, storage);
});
