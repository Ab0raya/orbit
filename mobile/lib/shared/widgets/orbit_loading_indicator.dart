import 'package:flutter/material.dart';

/// Orbit pulsing logo loading indicator.
///
/// Shows the solid Orbit logo and pulses its opacity between [minOpacity]
/// and [maxOpacity] over [duration], giving a smooth breathing animation.
///
/// Usage:
/// ```dart
/// const OrbitLoadingIndicator()          // default 48×48 centred
/// OrbitLoadingIndicator(size: 64)        // larger
/// OrbitLoadingIndicator(size: 32, label: 'Loading…')  // with label
/// ```
class OrbitLoadingIndicator extends StatefulWidget {
  final double size;
  final String? label;
  final double minOpacity;
  final double maxOpacity;
  final Duration duration;

  const OrbitLoadingIndicator({
    super.key,
    this.size = 48,
    this.label,
    this.minOpacity = 0.15,
    this.maxOpacity = 1.0,
    this.duration = const Duration(milliseconds: 1100),
  });

  @override
  State<OrbitLoadingIndicator> createState() => _OrbitLoadingIndicatorState();
}

class _OrbitLoadingIndicatorState extends State<OrbitLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _opacity = Tween<double>(begin: widget.minOpacity, end: widget.maxOpacity)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _opacity,
          builder: (context, child) {
            return Opacity(
              opacity: _opacity.value,
              child: child,
            );
          },
          child: Image.asset(
            'assets/images/orbit_logo_solid.png',
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: _opacity,
            builder: (context, child) => Opacity(
              opacity: (_opacity.value * 0.7).clamp(0.0, 1.0),
              child: child,
            ),
            child: Text(
              widget.label!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Centered full-area loading overlay using OrbitLoadingIndicator.
/// Wrap the body of a screen to show during async operations.
class OrbitLoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final String? label;
  final double size;
  final Color barrierColor;

  const OrbitLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.label,
    this.size = 56,
    this.barrierColor = const Color(0xCC000000),
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: barrierColor,
            alignment: Alignment.center,
            child: OrbitLoadingIndicator(size: size, label: label),
          ),
      ],
    );
  }
}
