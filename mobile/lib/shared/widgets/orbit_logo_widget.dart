import 'package:flutter/material.dart';

/// Primary Orbit logo widget — uses the real user-provided PNG assets.
/// [variant] selects between:
///   - 'silver' : silver gradient logo (default, great on dark backgrounds)
///   - 'solid'  : solid white logo
class OrbitLogoWidget extends StatelessWidget {
  final double size;
  final String variant; // 'silver' | 'solid'

  const OrbitLogoWidget({
    super.key,
    this.size = 28,
    this.variant = 'silver',
  });

  @override
  Widget build(BuildContext context) {
    final assetPath = variant == 'solid'
        ? 'assets/images/orbit_logo_solid.png'
        : 'assets/images/orbit_logo_silver.png';

    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// Large decorative version of the Orbit logo — used as a hero graphic.
/// Wraps OrbitLogoWidget with a glow effect for visual impact.
class OrbitEclipseGraphic extends StatelessWidget {
  final double size;
  final String variant;

  const OrbitEclipseGraphic({
    super.key,
    this.size = 120,
    this.variant = 'silver',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.08),
            blurRadius: 40,
            spreadRadius: 8,
          ),
        ],
      ),
      child: OrbitLogoWidget(size: size, variant: variant),
    );
  }
}
