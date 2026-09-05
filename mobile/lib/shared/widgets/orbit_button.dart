import 'package:flutter/material.dart';
import '../theme/orbit_colors.dart';
import 'orbit_loading_indicator.dart';

enum OrbitButtonVariant {
  primary,
  secondary,
  danger,
  outline,
}

class OrbitButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? icon;
  final OrbitButtonVariant variant;
  final double? width;

  const OrbitButton({
    super.key,
    String? label,
    String? text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.variant = OrbitButtonVariant.primary,
    this.width,
  }) : label = label ?? text ?? '';

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    BorderSide border = BorderSide.none;

    switch (variant) {
      case OrbitButtonVariant.primary:
        bg = OrbitColors.orbitAccent;
        fg = Colors.black;
        break;
      case OrbitButtonVariant.secondary:
        bg = OrbitColors.orbitSurfaceElevated;
        fg = OrbitColors.orbitTextPrimary;
        border = const BorderSide(color: OrbitColors.orbitBorder);
        break;
      case OrbitButtonVariant.danger:
        bg = OrbitColors.orbitError.withOpacity(0.15);
        fg = OrbitColors.orbitError;
        border = BorderSide(color: OrbitColors.orbitError.withOpacity(0.3));
        break;
      case OrbitButtonVariant.outline:
        bg = Colors.transparent;
        fg = OrbitColors.orbitTextSecondary;
        border = const BorderSide(color: OrbitColors.orbitBorder);
        break;
    }

    final childWidget = isLoading
        ? const OrbitLoadingIndicator(
            size: 22,
            minOpacity: 0.25,
            maxOpacity: 1.0,
            duration: Duration(milliseconds: 800),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 8)],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          );

    final button = ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withOpacity(0.4),
        disabledForegroundColor: fg.withOpacity(0.4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: border,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      child: childWidget,
    );

    if (width != null) {
      return SizedBox(width: width, child: button);
    }
    return button;
  }
}
