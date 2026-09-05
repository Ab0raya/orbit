import 'package:flutter/material.dart';
import '../theme/orbit_colors.dart';

enum StatusType {
  online,
  offline,
  warning,
  cyan,
}

class StatusPill extends StatelessWidget {
  final String label;
  final StatusType type;

  const StatusPill({
    super.key,
    String? label,
    String? text,
    this.type = StatusType.online,
  }) : label = label ?? text ?? '';

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    Color bgColor;
    Color textColor;

    switch (type) {
      case StatusType.online:
        dotColor = OrbitColors.orbitAccent;
        bgColor = OrbitColors.orbitAccent.withOpacity(0.12);
        textColor = OrbitColors.orbitAccent;
        break;
      case StatusType.offline:
        dotColor = OrbitColors.orbitError;
        bgColor = OrbitColors.orbitError.withOpacity(0.12);
        textColor = OrbitColors.orbitError;
        break;
      case StatusType.warning:
        dotColor = OrbitColors.orbitWarning;
        bgColor = OrbitColors.orbitWarning.withOpacity(0.12);
        textColor = OrbitColors.orbitWarning;
        break;
      case StatusType.cyan:
        dotColor = OrbitColors.orbitAccentCyan;
        bgColor = OrbitColors.orbitAccentCyan.withOpacity(0.12);
        textColor = OrbitColors.orbitAccentCyan;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dotColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withOpacity(0.6),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
