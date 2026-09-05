import 'package:flutter/material.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../models/project_models.dart';

class ProjectTile extends StatelessWidget {
  final ProjectSummary project;
  final VoidCallback onTap;

  const ProjectTile({
    super.key,
    required this.project,
    required this.onTap,
  });

  Color _getFrameworkColor(String type) {
    switch (type.toLowerCase()) {
      case 'flutter':
        return Colors.lightBlueAccent;
      case 'rust':
        return Colors.orangeAccent;
      case 'node':
        return Colors.greenAccent;
      case 'python':
        return Colors.amberAccent;
      case 'android':
        return Colors.lightGreenAccent;
      default:
        return OrbitColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return OrbitCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: onTap,
      child: Row(
        children: [
          // Project type icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: OrbitColors.surfaceHighlight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: project.isGit
                    ? OrbitColors.primary.withValues(alpha: 0.3)
                    : OrbitColors.borderSubtle,
              ),
            ),
            child: Icon(
              project.isGit ? Icons.folder_special : Icons.folder,
              color: project.isGit
                  ? OrbitColors.primary
                  : _getFrameworkColor(project.projectType),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),

          // Project details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        project.name,
                        style: const TextStyle(
                          color: OrbitColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Framework pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getFrameworkColor(project.projectType)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _getFrameworkColor(project.projectType)
                              .withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        project.projectType.toUpperCase(),
                        style: TextStyle(
                          color: _getFrameworkColor(project.projectType),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  project.path,
                  style: const TextStyle(
                    color: OrbitColors.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (project.isGit && project.git != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.fork_right,
                        color: OrbitColors.accentCyan,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        project.git!.branch,
                        style: const TextStyle(
                          color: OrbitColors.accentCyan,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 10),
                      StatusPill(
                        text: project.git!.isDirty ? 'MODIFIED' : 'CLEAN',
                        type: project.git!.isDirty
                            ? StatusType.warning
                            : StatusType.online,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right,
            color: OrbitColors.textMuted,
            size: 18,
          ),
        ],
      ),
    );
  }
}
