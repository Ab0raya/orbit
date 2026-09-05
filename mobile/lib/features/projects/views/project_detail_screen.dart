import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_button.dart';
import '../../../shared/widgets/orbit_card.dart';
import '../../ai/views/ai_command_center_screen.dart';
import '../../files/views/file_explorer_screen.dart';
import '../../../protocol/models/ai_context.dart';
import '../../terminal/views/terminal_screen.dart';
import '../controllers/project_controller.dart';
import '../models/project_models.dart';
import '../widgets/branch_selector.dart';
import '../widgets/changed_file_tile.dart';
import '../widgets/git_status_summary.dart';
import 'git_history_screen.dart';
import '../../scripts/views/scripts_screen.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  final String projectPath;
  final String projectName;

  const ProjectDetailScreen({
    super.key,
    required this.projectPath,
    required this.projectName,
  });

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh git state on enter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(projectControllerProvider(widget.projectPath).notifier)
          .refreshGitStatus();
    });
  }

  void _showCommitDialog(BuildContext context, ProjectController controller) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OrbitColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: OrbitColors.borderSubtle),
        ),
        title: const Text(
          'COMMIT CHANGES',
          style: TextStyle(
            color: OrbitColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: textController,
              autofocus: true,
              maxLines: 3,
              style: const TextStyle(
                color: OrbitColors.textPrimary,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              decoration: const InputDecoration(
                hintText: 'Enter commit message...',
                hintStyle: TextStyle(color: OrbitColors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: OrbitColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: OrbitColors.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: OrbitColors.textMuted)),
          ),
          OrbitButton(
            text: 'Commit',
            onPressed: () async {
              final msg = textController.text.trim();
              if (msg.isNotEmpty) {
                Navigator.pop(ctx);
                await controller.commit(msg);
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectControllerProvider(widget.projectPath));
    final controller =
        ref.read(projectControllerProvider(widget.projectPath).notifier);

    // Show snackbar messages
    ref.listen(projectControllerProvider(widget.projectPath), (prev, next) {
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: OrbitColors.error,
          ),
        );
      }
      if (next.successMessage != null &&
          next.successMessage != prev?.successMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.successMessage!),
            backgroundColor: OrbitColors.primary,
          ),
        );
      }
    });

    final project = state.project;

    return Scaffold(
      backgroundColor: OrbitColors.backgroundDark,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.projectName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              widget.projectPath,
              style: const TextStyle(
                fontSize: 10,
                color: OrbitColors.textMuted,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: OrbitColors.accentCyan),
            onPressed: state.isLoading
                ? null
                : () {
                    controller.loadProject();
                    controller.refreshGitStatus();
                  },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: state.isLoading && project == null
          ? const Center(
              child: OrbitLoadingIndicator(size: 40))
          : _buildContent(context, state, controller),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ProjectDetailState state,
    ProjectController controller,
  ) {
    final project = state.project;
    if (project == null) {
      return Center(
        child: Text(
          state.errorMessage ?? 'Project not found',
          style: const TextStyle(color: OrbitColors.error),
        ),
      );
    }

    final git = project.git;

    return RefreshIndicator(
      color: OrbitColors.primary,
      backgroundColor: OrbitColors.surfaceDark,
      onRefresh: () async {
        await controller.loadProject();
        await controller.refreshGitStatus();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // Project Action Hub (Files, Terminal, History)
          _buildActionHub(context, project),

          // Git Section
          if (project.isGit && git != null) ...[
            GitStatusSummary(
              status: git,
              onSwitchBranch: () {
                if (state.branches != null) {
                  BranchSelectorSheet.show(
                    context,
                    branches: state.branches!,
                    onSelectBranch: (b) => controller.checkoutBranch(b),
                    onCreateBranch: (n) => controller.createBranch(n),
                  );
                } else {
                  controller.loadBranches();
                }
              },
            ),

            // Commit button if changes exist
            if (!git.clean) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: OrbitButton(
                  text: 'Commit Changes (${git.staged.length} staged)',
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  isLoading: state.isCommitting,
                  onPressed: git.staged.isEmpty
                      ? null
                      : () => _showCommitDialog(context, controller),
                ),
              ),
            ],

            // Staged files
            if (git.staged.isNotEmpty) ...[
              _buildSectionHeader(
                title: 'STAGED CHANGES',
                count: git.staged.length,
                actionText: 'Unstage Selected',
                onAction: state.selectedStaged.isEmpty
                    ? null
                    : () => controller.unstageSelected(),
              ),
              ...git.staged.map((f) => ChangedFileTile(
                    file: f,
                    isSelected: state.selectedStaged.contains(f.path),
                    onSelected: (_) => controller.toggleStaged(f.path),
                  )),
            ],

            // Unstaged modified files
            if (git.unstaged.isNotEmpty) ...[
              _buildSectionHeader(
                title: 'MODIFIED (UNSTAGED)',
                count: git.unstaged.length,
                actionText: 'Stage Selected',
                onAction: state.selectedUnstaged.isEmpty
                    ? null
                    : () => controller.stageSelected(),
              ),
              ...git.unstaged.map((f) => ChangedFileTile(
                    file: f,
                    isSelected: state.selectedUnstaged.contains(f.path),
                    onSelected: (_) => controller.toggleUnstaged(f.path),
                  )),
            ],

            // Untracked files
            if (git.untracked.isNotEmpty) ...[
              _buildSectionHeader(
                title: 'UNTRACKED FILES',
                count: git.untracked.length,
                actionText: 'Stage Selected',
                onAction: state.selectedUntracked.isEmpty
                    ? null
                    : () => controller.stageSelected(),
              ),
              ...git.untracked.map((f) => ChangedFileTile(
                    file: f,
                    isSelected: state.selectedUntracked.contains(f.path),
                    onSelected: (_) => controller.toggleUntracked(f.path),
                  )),
            ],
          ] else ...[
            // Non-git project capabilities display
            OrbitCard(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PROJECT CAPABILITIES',
                    style: TextStyle(
                      color: OrbitColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildCapabilityItem(Icons.check_circle, 'Files', OrbitColors.primary),
                      const SizedBox(width: 16),
                      _buildCapabilityItem(Icons.check_circle, 'Terminal', OrbitColors.accentCyan),
                      const SizedBox(width: 16),
                      _buildCapabilityItem(Icons.check_circle, 'Orbit AI', OrbitColors.primary),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.remove_circle_outline, size: 14, color: OrbitColors.textMuted),
                      SizedBox(width: 6),
                      Text(
                        'Git: Not available (non-Git directory)',
                        style: TextStyle(
                          color: OrbitColors.textMuted,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionHub(BuildContext context, ProjectInfo project) {
    return OrbitCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                project.name,
                style: const TextStyle(
                  color: OrbitColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: OrbitColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: OrbitColors.borderSubtle),
                ),
                child: Text(
                  project.projectType.toUpperCase(),
                  style: const TextStyle(
                    color: OrbitColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 1: Files, Terminal, Scripts
          Row(
            children: [
              // Files Button
              Expanded(
                child: _buildActionButton(
                  icon: Icons.folder_open,
                  label: 'Files',
                  color: OrbitColors.primary,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FileExplorerScreen(
                          initialPath: project.path,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Terminal Button
              Expanded(
                child: _buildActionButton(
                  icon: Icons.terminal,
                  label: 'Terminal',
                  color: OrbitColors.accentCyan,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TerminalScreen(
                          initialCwd: project.path,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Scripts Button
              Expanded(
                child: _buildActionButton(
                  icon: Icons.play_circle_outline,
                  label: 'Scripts',
                  color: const Color(0xFF10B981),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScriptsScreen(
                          projectPath: project.path,
                          projectName: project.name,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Commits & Ask Orbit AI
          Row(
            children: [
              // Git History Button
              if (project.isGit) ...[
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.history,
                    label: 'Commits',
                    color: Colors.purpleAccent,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GitHistoryScreen(
                            projectPath: project.path,
                            projectName: project.name,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Ask Orbit AI Button
              Expanded(
                child: _buildActionButton(
                  icon: Icons.auto_awesome,
                  label: 'Ask Orbit AI',
                  color: Colors.amberAccent,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AiCommandCenterScreen(
                          initialContext: AiContext.fromProject(
                            path: project.path,
                            name: project.name,
                            projectType: project.projectType,
                            isGit: project.isGit,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: OrbitColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required int count,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: OrbitColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: OrbitColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: OrbitColors.textPrimary,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (actionText != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(40, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionText,
                style: const TextStyle(
                  color: OrbitColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCapabilityItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
