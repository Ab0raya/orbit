import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/core/networking/connection_state.dart';

void main() {
  group('ConnectionState transitions & separate transport/pairing modeling', () {
    test('Initial state is disconnected', () {
      const state = OrbitConnectionState();
      expect(state.status, OrbitConnectionStatus.disconnected);
      expect(state.isConnected, false);
      expect(state.isPaired, false);
      expect(state.isUnpaired, false);
    });

    test('State copyWith updates connection status and distinct flags', () {
      const state = OrbitConnectionState();
      final connecting = state.copyWith(
        status: OrbitConnectionStatus.connecting,
        host: '192.168.1.100',
        port: 4371,
      );
      expect(connecting.status, OrbitConnectionStatus.connecting);
      expect(connecting.isConnected, false);
      expect(connecting.isPaired, false);

      // Connected unpaired: transport active, but pairing not complete
      final connectedUnpaired = connecting.copyWith(
        status: OrbitConnectionStatus.connectedUnpaired,
      );
      expect(connectedUnpaired.isConnected, true);
      expect(connectedUnpaired.isUnpaired, true);
      expect(connectedUnpaired.isPaired, false);

      // Pairing state: in-progress verification
      final pairing = connectedUnpaired.copyWith(
        status: OrbitConnectionStatus.pairing,
      );
      expect(pairing.isConnected, true);
      expect(pairing.isUnpaired, false);
      expect(pairing.isPaired, false);

      // Paired state: authenticated session established
      final paired = pairing.copyWith(
        status: OrbitConnectionStatus.paired,
        deviceId: 'dev_stable_123',
      );
      expect(paired.isConnected, true);
      expect(paired.isUnpaired, false);
      expect(paired.isPaired, true);
      expect(paired.deviceId, 'dev_stable_123');

      // Reconnecting state
      final reconnecting = paired.copyWith(
        status: OrbitConnectionStatus.reconnecting,
      );
      expect(reconnecting.isConnected, false);
      expect(reconnecting.isPaired, false);

      // Backwards-compatible alias
      expect(OrbitConnectionStatus.connected, OrbitConnectionStatus.connectedUnpaired);
    });
  });
}
