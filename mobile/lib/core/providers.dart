import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'networking/orbit_websocket_client.dart';
import 'networking/connection_state.dart';
import 'storage/local_storage.dart';
import '../protocol/messages/orbit_event.dart';

final localStorageProvider = Provider<ILocalStorage>((ref) {
  throw UnimplementedError('localStorageProvider must be initialized with an implementation');
});

final webSocketClientProvider = Provider<OrbitWebSocketClient>((ref) {
  final client = OrbitWebSocketClient();
  ref.onDispose(() => client.dispose());
  return client;
});

final orbitClientProvider = webSocketClientProvider;

final connectionStateProvider = StreamProvider<OrbitConnectionState>((ref) {
  final client = ref.watch(webSocketClientProvider);
  return client.stateStream;
});

final orbitEventsProvider = StreamProvider<OrbitEvent>((ref) {
  final client = ref.watch(webSocketClientProvider);
  return client.events;
});
