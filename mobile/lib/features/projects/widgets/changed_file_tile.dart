import 'package:flutter/material.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../models/project_models.dart';

class ChangedFileTile extends StatelessWidget {
  final GitFileChange file;
  final bool isSelected;
  final ValueChanged<bool?> onSelected;

  const ChangedFileTile({
    super.key,
    required this.file,
    required this.isSelected,
    required this.onSelected,
  });

  Color _getStatusColor() {
    switch (file.status.toLowerCase()) {
      case 'added':
        return OrbitColors.primary;
      case 'modified':
        return OrbitColors.warning;
      case 'deleted':
        return OrbitColors.error;
      case 'untracked':
        return OrbitColors.accentCyan;
      case 'renamed':
        return Colors.purpleAccent;
      default:
        return OrbitColors.textMuted;
    }
  }

  String _getStatusPrefix() {
    switch (file.status.toLowerCase()) {
      case 'added':
        return 'A';
      case 'modified':
        return 'M';
      case 'deleted':
        return 'D';
      case 'untracked':
        return '??';
      case 'renamed':
        return 'R';
      default:
        return '•';
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onSelected(!isSelected),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            // Checkbox
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: isSelected,
                onChanged: onSelected,
                activeColor: OrbitColors.primary,
                checkColor: OrbitColors.backgroundDark,
                side: const BorderSide(color: OrbitColors.borderSubtle),
              ),
            ),
            const SizedBox(width: 8),

            // Status indicator
            Container(
              width: 26,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _getStatusColor().withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _getStatusPrefix(),
                style: TextStyle(
                  color: _getStatusColor(),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Path
            Expanded(
              child: Text(
                file.path,
                style: const TextStyle(
                  color: OrbitColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
