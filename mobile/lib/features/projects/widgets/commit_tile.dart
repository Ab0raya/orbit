import 'package:flutter/material.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_card.dart';
import '../models/project_models.dart';

class CommitTile extends StatelessWidget {
  final GitCommit commit;

  const CommitTile({
    super.key,
    required this.commit,
  });

  String _formatTimestamp(int ts) {
    if (ts == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return OrbitCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Short hash
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: OrbitColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: OrbitColors.accentCyan.withValues(alpha: 0.3)),
                ),
                child: Text(
                  commit.shortHash,
                  style: const TextStyle(
                    color: OrbitColors.accentCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const Spacer(),
              // Relative time
              Text(
                _formatTimestamp(commit.timestamp),
                style: const TextStyle(
                  color: OrbitColors.textMuted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Message
          Text(
            commit.message,
            style: const TextStyle(
              color: OrbitColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),

          // Author
          Row(
            children: [
              const Icon(
                Icons.person_outline,
                color: OrbitColors.textMuted,
                size: 13,
              ),
              const SizedBox(width: 4),
              Text(
                commit.author,
                style: const TextStyle(
                  color: OrbitColors.textMuted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
