import 'package:flutter/material.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../models/project_models.dart';

class GitStatusSummary extends StatelessWidget {
  final GitStatus status;
  final VoidCallback onSwitchBranch;

  const GitStatusSummary({
    super.key,
    required this.status,
    required this.onSwitchBranch,
  });

  @override
  Widget build(BuildContext context) {
    return OrbitCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branch row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.fork_right,
                    color: OrbitColors.accentCyan,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status.branch,
                    style: const TextStyle(
                      color: OrbitColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  StatusPill(
                    text: status.clean ? 'CLEAN' : 'DIRTY',
                    type: status.clean ? StatusType.online : StatusType.warning,
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onSwitchBranch,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: OrbitColors.surfaceHighlight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: OrbitColors.borderSubtle),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz,
                              color: OrbitColors.accentCyan, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Switch',
                            style: TextStyle(
                              color: OrbitColors.accentCyan,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: OrbitColors.borderSubtle),
          const SizedBox(height: 10),

          // Counters row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCounter(
                'Staged',
                status.staged.length,
                OrbitColors.primary,
              ),
              _buildCounter(
                'Modified',
                status.unstaged.length,
                OrbitColors.warning,
              ),
              _buildCounter(
                'Untracked',
                status.untracked.length,
                OrbitColors.accentCyan,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCounter(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: OrbitColors.textMuted,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
