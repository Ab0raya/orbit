import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/providers.dart';
import 'core/storage/shared_prefs_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await SharedPrefsStorage.init();

  runApp(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
      ],
      child: const OrbitApp(),
    ),
  );
}
