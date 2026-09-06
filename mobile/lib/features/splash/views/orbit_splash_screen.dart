import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../connection/views/connection_screen.dart';

/// Dedicated cinematic Orbit splash screen presenting the custom Orbit cosmic artwork.
///
/// Provides a seamless, full-screen, edge-to-edge splash experience that blends
/// directly from the native launch bridge into Flutter rendering, with zero blank
/// frames and no redundant UI chrome.
class OrbitSplashScreen extends StatefulWidget {
  final Duration duration;
  final Widget? nextScreen;

  const OrbitSplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 1800),
    this.nextScreen,
  });

  static const String splashAssetPath = 'assets/images/orbit_splash_screen.png';

  @override
  State<OrbitSplashScreen> createState() => _OrbitSplashScreenState();
}

class _OrbitSplashScreenState extends State<OrbitSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  Timer? _navigationTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    // Subtle fade in from the black native launch bridge
    _animController.forward();

    _scheduleNavigation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage(OrbitSplashScreen.splashAssetPath), context);
  }

  void _scheduleNavigation() {
    _navigationTimer = Timer(widget.duration, () {
      if (!mounted) return;
      _navigateToNext();
    });
  }

  void _navigateToNext() {
    if (_navigated || !mounted) return;
    _navigated = true;

    final targetScreen = widget.nextScreen ?? const ConnectionScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Image.asset(
                OrbitSplashScreen.splashAssetPath,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
