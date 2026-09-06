import 'package:flutter/material.dart';
import 'shared/theme/orbit_theme.dart';
import 'features/splash/views/orbit_splash_screen.dart';

class OrbitApp extends StatelessWidget {
  const OrbitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orbit Mobile',
      debugShowCheckedModeBanner: false,
      theme: OrbitTheme.darkTheme,
      home: const OrbitSplashScreen(),
    );
  }
}

