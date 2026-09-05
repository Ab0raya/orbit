import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/orbit_websocket_client.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/providers.dart';
import '../../../protocol/models/pairing_models.dart';
import '../../../protocol/models/system_info.dart';

import '../../../core/networking/connection_manager.dart';

class ConnectionScreenState {
  final String host;
  final int port;
  final String? tailscaleHost;
  final ConnectionPathType selectedPath;
  final bool isConnecting;
  final String? errorMessage;
  final PairedDeviceRecord? savedPairedDevice;
  final bool hasWelcome;

  const ConnectionScreenState({
    this.host = '127.0.0.1',
    this.port = 4371,
    this.tailscaleHost,
    this.selectedPath = ConnectionPathType.localLan,
    this.isConnecting = false,
    this.errorMessage,
    this.savedPairedDevice,
    this.hasWelcome = false,
  });

  ConnectionScreenState copyWith({
    String? host,
    int? port,
    String? tailscaleHost,
    ConnectionPathType? selectedPath,
    bool? isConnecting,
    String? errorMessage,
    PairedDeviceRecord? savedPairedDevice,
    bool? hasWelcome,
    bool clearError = false,
  }) {
    return ConnectionScreenState(
      host: host ?? this.host,
      port: port ?? this.port,
      tailscaleHost: tailscaleHost ?? this.tailscaleHost,
      selectedPath: selectedPath ?? this.selectedPath,
      isConnecting: isConnecting ?? this.isConnecting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      savedPairedDevice: savedPairedDevice ?? this.savedPairedDevice,
      hasWelcome: hasWelcome ?? this.hasWelcome,
    );
  }
}

class ConnectionController extends StateNotifier<ConnectionScreenState> {
  final OrbitWebSocketClient _client;
  final ILocalStorage _storage;
  StreamSubscription? _eventSub;

  ConnectionController(this._client, this._storage)
      : super(const ConnectionScreenState()) {
    _loadSavedDevice();
  }

  Future<void> reloadSavedDevice() async {
    await _loadSavedDevice();
    await refreshDeviceInfo();
  }

  Future<PairedDeviceRecord?> _enrichDeviceFromSystemInfo({
    required PairedDeviceRecord currentRecord,
    String? preferredPath,
  }) async {
    try {
      final sysRes = await _client.sendRequest(
        'system.info',
        payload: {'refresh': true},
        timeout: const Duration(milliseconds: 3000),
      );
      if (sysRes.success && sysRes.payload != null) {
        final sys = SystemInfo.fromJson(sysRes.payload!);
        final ts = sys.tailscale;
        final String? freshTs = (ts != null && ts.isConnected && ts.ip != null && ts.ip!.isNotEmpty)
            ? ts.ip
            : currentRecord.tailscaleAddress;
        final String? freshState = ts?.state ?? currentRecord.tailscaleState;
        final String freshName = sys.hostname.isNotEmpty ? sys.hostname : currentRecord.pcDisplayName;

        final updated = PairedDeviceRecord(
          deviceId: currentRecord.deviceId,
          pcAddress: currentRecord.pcAddress,
          pcPort: currentRecord.pcPort,
          tailscaleAddress: freshTs,
          pcDisplayName: freshName,
          mobileDisplayName: currentRecord.mobileDisplayName,
          pairedAt: currentRecord.pairedAt,
          lastUsedPath: preferredPath ?? currentRecord.lastUsedPath,
          tailscaleState: freshState,
        );
        await _storage.savePairedDevice(updated);
        return updated;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> refreshDeviceInfo({bool showLoading = false}) async {
    final paired = await _storage.getPairedDevice();
    if (paired == null) return false;

    if (showLoading) {
      state = state.copyWith(isConnecting: true, clearError: true);
    }

    try {
      // 1. If currently connected & paired, query system.info over active socket
      if (_client.currentState.isConnected && _client.currentState.isPaired) {
        final enriched = await _enrichDeviceFromSystemInfo(currentRecord: paired);
        if (enriched != null) {
          state = state.copyWith(
            isConnecting: false,
            savedPairedDevice: enriched,
            tailscaleHost: enriched.tailscaleAddress,
          );
          return true;
        }
      }

      // 2. If disconnected, probe Desktop over LAN or Tailscale
      final installationId = await _storage.getOrCreateInstallationDeviceId();
      final probeHosts = <String>[];
      if (paired.pcAddress.isNotEmpty) probeHosts.add(paired.pcAddress);
      if (paired.tailscaleAddress != null && paired.tailscaleAddress!.isNotEmpty) {
        if (!probeHosts.contains(paired.tailscaleAddress!)) {
          probeHosts.add(paired.tailscaleAddress!);
        }
      }

      for (final host in probeHosts) {
        OrbitWebSocketClient? probeClient;
        StreamSubscription? sub;
        try {
          probeClient = OrbitWebSocketClient();
          final welcomeCompleter = Completer<bool>();
          sub = probeClient.events.listen((ev) {
            if (ev.event == 'welcome') {
              if (!welcomeCompleter.isCompleted) welcomeCompleter.complete(true);
            }
          });

          await probeClient.connect(host, paired.pcPort).timeout(const Duration(milliseconds: 1500));
          await welcomeCompleter.future.timeout(const Duration(milliseconds: 1500), onTimeout: () => true);
          await sub.cancel();
          sub = null;

          final resumeRes = await probeClient.sendRequest(
            'session.resume',
            payload: {'deviceId': installationId},
            timeout: const Duration(milliseconds: 2000),
          );

          if (resumeRes.success && resumeRes.payload?['resumed'] == true) {
            probeClient.markPaired(installationId);
            final sysRes = await probeClient.sendRequest(
              'system.info',
              payload: {'refresh': true},
              timeout: const Duration(milliseconds: 2000),
            );

            if (sysRes.success && sysRes.payload != null) {
              final sys = SystemInfo.fromJson(sysRes.payload!);
              final ts = sys.tailscale;
              final String? freshTs = (ts != null && ts.isConnected && ts.ip != null && ts.ip!.isNotEmpty)
                  ? ts.ip
                  : paired.tailscaleAddress;
              final String? freshState = ts?.state ?? paired.tailscaleState;
              final String freshName = sys.hostname.isNotEmpty ? sys.hostname : paired.pcDisplayName;

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
              await _storage.savePairedDevice(updated);

              state = state.copyWith(
                isConnecting: false,
                savedPairedDevice: updated,
                tailscaleHost: updated.tailscaleAddress,
                host: updated.pcAddress,
              );
              return true;
            }
          }
        } catch (_) {
          // Continue to next probe host if this one fails
        } finally {
          await sub?.cancel();
          probeClient?.dispose();
        }
      }
    } finally {
      if (showLoading && state.isConnecting) {
        state = state.copyWith(isConnecting: false);
      }
    }

    return false;
  }

  Future<void> _loadSavedDevice() async {
    final paired = await _storage.getPairedDevice();
    final recent = await _storage.getRecentConnection();

    if (paired != null) {
      ConnectionPathType path = ConnectionPathType.localLan;
      if (paired.lastUsedPath == 'tailscale') {
        path = ConnectionPathType.tailscale;
      }

      state = state.copyWith(
        host: paired.pcAddress,
        port: paired.pcPort,
        tailscaleHost: paired.tailscaleAddress,
        selectedPath: path,
        savedPairedDevice: paired,
      );
    } else if (recent != null) {
      state = state.copyWith(
        host: recent['host'] as String? ?? '127.0.0.1',
        port: recent['port'] as int? ?? 4371,
      );
    }
  }

  void updateHost(String host) {
    state = state.copyWith(host: host.trim(), clearError: true);
  }

  void updateTailscaleHost(String host) {
    state = state.copyWith(tailscaleHost: host.trim(), clearError: true);
  }

  void selectPath(ConnectionPathType path) {
    state = state.copyWith(selectedPath: path, clearError: true);
  }

  void updatePort(int port) {
    state = state.copyWith(port: port, clearError: true);
  }

  Future<bool> connect({String? customHost, int? customPort, ConnectionPathType? specificPath}) async {
    final path = specificPath ?? state.selectedPath;
    String host;
    if (customHost != null) {
      host = customHost;
    } else if (path == ConnectionPathType.tailscale && state.tailscaleHost != null && state.tailscaleHost!.isNotEmpty) {
      host = state.tailscaleHost!;
    } else {
      host = state.host;
    }
    final port = customPort ?? state.port;

    state = state.copyWith(
      isConnecting: true,
      clearError: true,
      hasWelcome: false,
    );

    final welcomeCompleter = Completer<bool>();
    _eventSub?.cancel();
    _eventSub = _client.events.listen((event) {
      if (event.event == 'welcome') {
        if (!welcomeCompleter.isCompleted) {
          welcomeCompleter.complete(true);
        }
      }
    });

    bool connectedOk = false;
    String activeHost = host;
    ConnectionPathType activePath = path;

    try {
      await _client.connect(host, port);
      connectedOk = true;
    } catch (e) {
      // If user was on Local LAN and it failed, but we have a Tailscale host, try Tailscale fallback!
      if (path == ConnectionPathType.localLan &&
          state.tailscaleHost != null &&
          state.tailscaleHost!.isNotEmpty &&
          state.tailscaleHost != host) {
        try {
          await _client.connect(state.tailscaleHost!, port);
          connectedOk = true;
          activeHost = state.tailscaleHost!;
          activePath = ConnectionPathType.tailscale;
        } catch (_) {
          // Both failed
        }
      }
    }

    if (!connectedOk) {
      state = state.copyWith(
        isConnecting: false,
        errorMessage: 'Connection failed to $host:$port',
      );
      return false;
    }

    try {
      await _storage.saveRecentConnection(activeHost, port);

      // Wait up to 3s for welcome event
      await welcomeCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => true, // Fallback if welcome was missed
      );

      // Verify connection with ping
      await _client.sendPing();

      // Attempt session.resume if previously paired to this host & port
      final installationId = await _storage.getOrCreateInstallationDeviceId();
      final pairedRecord = await _storage.getPairedDevice();
      if (pairedRecord != null &&
          (pairedRecord.pcAddress == activeHost ||
              pairedRecord.tailscaleAddress == activeHost ||
              pairedRecord.pcAddress == host) &&
          pairedRecord.pcPort == port) {
        try {
          final resumeRes = await _client.sendRequest(
            'session.resume',
            payload: {'deviceId': installationId},
          );
          if (resumeRes.success && resumeRes.payload?['resumed'] == true) {
            _client.markPaired(installationId);
            final updated = PairedDeviceRecord(
              deviceId: pairedRecord.deviceId,
              pcAddress: pairedRecord.pcAddress,
              pcPort: pairedRecord.pcPort,
              tailscaleAddress: pairedRecord.tailscaleAddress ?? state.tailscaleHost,
              pcDisplayName: pairedRecord.pcDisplayName,
              mobileDisplayName: pairedRecord.mobileDisplayName,
              pairedAt: pairedRecord.pairedAt,
              lastUsedPath: activePath.name,
              tailscaleState: pairedRecord.tailscaleState,
            );

            // Fetch fresh system.info to enrich Tailscale and hostname
            final enriched = await _enrichDeviceFromSystemInfo(
              currentRecord: updated,
              preferredPath: activePath.name,
            );
            final finalRecord = enriched ?? updated;
            if (enriched == null) {
              await _storage.savePairedDevice(updated);
            }
            state = state.copyWith(
              savedPairedDevice: finalRecord,
              tailscaleHost: finalRecord.tailscaleAddress,
              selectedPath: activePath,
            );
          } else {
            // Resume failed: remove invalid pairing record from storage
            await _storage.clearPairedDevice();
            _client.markUnpaired();
            state = state.copyWith(savedPairedDevice: null);
          }
        } catch (_) {
          // If resume fails with an error/unauthorized, clear paired record
          await _storage.clearPairedDevice();
          _client.markUnpaired();
          state = state.copyWith(savedPairedDevice: null);
        }
      }

      state = state.copyWith(
        isConnecting: false,
        hasWelcome: true,
        selectedPath: activePath,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isConnecting: false,
        errorMessage: 'Connection failed: ${e.toString()}',
      );
      return false;
    }
  }

  Future<bool> pairWithQr(OrbitPairingQrPayload qr) async {
    if (qr.isExpired) {
      state = state.copyWith(
        errorMessage: 'Pairing QR code has expired. Please regenerate on PC.',
      );
      return false;
    }

    state = state.copyWith(
      host: qr.host,
      tailscaleHost: qr.tailscaleHost,
      port: qr.port,
      isConnecting: true,
      clearError: true,
      hasWelcome: false,
    );

    final welcomeCompleter = Completer<bool>();
    _eventSub?.cancel();
    _eventSub = _client.events.listen((event) {
      if (event.event == 'welcome') {
        if (!welcomeCompleter.isCompleted) {
          welcomeCompleter.complete(true);
        }
      }
    });

    String targetHost = qr.host;
    ConnectionPathType usedPath = ConnectionPathType.localLan;
    bool connected = false;

    // Prefer LAN first
    try {
      await _client.connect(qr.host, qr.port);
      connected = true;
    } catch (_) {
      // If LAN fails and Tailscale host is available, fall back to Tailscale
      if (qr.tailscaleHost != null && qr.tailscaleHost!.isNotEmpty) {
        try {
          await _client.connect(qr.tailscaleHost!, qr.port);
          connected = true;
          targetHost = qr.tailscaleHost!;
          usedPath = ConnectionPathType.tailscale;
        } catch (e2) {
          // Both failed
        }
      }
    }

    if (!connected) {
      _client.markUnpaired();
      state = state.copyWith(
        isConnecting: false,
        errorMessage: 'Could not connect to PC via Local LAN${qr.tailscaleHost != null ? ' or Tailscale' : ''}',
      );
      return false;
    }

    try {
      await _storage.saveRecentConnection(targetHost, qr.port);

      // Wait up to 3s for welcome event
      await welcomeCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => true,
      );

      // Send ping to verify socket
      await _client.sendPing();

      // Enter pairing state
      _client.markPairing();

      final platform = Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'linux');
      final deviceName = Platform.isIOS ? 'iPhone' : (Platform.isAndroid ? 'Android Phone' : 'Linux Client');
      final installationDeviceId = await _storage.getOrCreateInstallationDeviceId();

      final payload = PairingPayload(
        code: qr.code,
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
          isConnecting: false,
          errorMessage: response.error?.message ?? 'Pairing verification failed',
        );
        return false;
      }

      final result = PairingResult.fromJson(response.payload ?? {});
      if (!result.paired || result.deviceId.isEmpty) {
        _client.markUnpaired();
        state = state.copyWith(
          isConnecting: false,
          errorMessage: 'Pairing failed: Invalid response from PC',
        );
        return false;
      }

      _client.markPaired(result.deviceId);

      // Save initial paired device record with QR data
      final initialRecord = PairedDeviceRecord(
        deviceId: result.deviceId,
        pcAddress: qr.host,
        pcPort: qr.port,
        tailscaleAddress: qr.tailscaleHost,
        pcDisplayName: 'Developer PC (${qr.host})',
        mobileDisplayName: deviceName,
        pairedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        lastUsedPath: usedPath.name,
      );

      // Fetch fresh authoritative system.info to enrich Tailscale and hostname
      final enriched = await _enrichDeviceFromSystemInfo(
        currentRecord: initialRecord,
        preferredPath: usedPath.name,
      );
      final finalRecord = enriched ?? initialRecord;
      if (enriched == null) {
        await _storage.savePairedDevice(initialRecord);
      }

      state = state.copyWith(
        isConnecting: false,
        hasWelcome: true,
        selectedPath: usedPath,
        savedPairedDevice: finalRecord,
        tailscaleHost: finalRecord.tailscaleAddress,
      );
      return true;
    } catch (e) {
      _client.markUnpaired();
      state = state.copyWith(
        isConnecting: false,
        errorMessage: 'Pairing failed: ${e.toString()}',
      );
      return false;
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}

final connectionControllerProvider =
    StateNotifierProvider<ConnectionController, ConnectionScreenState>((ref) {
  final client = ref.watch(webSocketClientProvider);
  final storage = ref.watch(localStorageProvider);
  return ConnectionController(client, storage);
});
