import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../controllers/projects_controller.dart';
import '../widgets/project_tile.dart';
import 'project_detail_screen.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  const ProjectsScreen({super.key, this.onBack});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectsControllerProvider);
    final controller = ref.read(projectsControllerProvider.notifier);

    return Scaffold(
      backgroundColor: OrbitColors.backgroundDark,
      appBar: AppBar(
        leading: (widget.onBack != null || Navigator.of(context).canPop())
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                tooltip: 'Back',
                onPressed: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              )
            : null,
        title: const Text(
          'PROJECTS',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontFamily: 'monospace',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: OrbitColors.accentCyan),
            onPressed: state.isLoading ? null : () => controller.refresh(),
            tooltip: 'Refresh projects',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (q) => controller.setSearchQuery(q),
              style: const TextStyle(
                color: OrbitColors.textPrimary,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Search projects by name, path, tech...',
                hintStyle: const TextStyle(color: OrbitColors.textMuted),
                prefixIcon:
                    const Icon(Icons.search, color: OrbitColors.textMuted, size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: OrbitColors.textMuted, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          controller.setSearchQuery('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: OrbitColors.surfaceHighlight,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: OrbitColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: OrbitColors.primary),
                ),
              ),
            ),
          ),

          // Roots Selector Chips
          if (state.roots.isNotEmpty) ...[
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildRootChip(
                    label: 'All Roots',
                    isSelected: state.selectedRoot == null,
                    onTap: () => controller.selectRoot(null),
                  ),
                  ...state.roots.map((root) => _buildRootChip(
                        label: root.name,
                        isSelected: state.selectedRoot == root.path,
                        onTap: () => controller.selectRoot(root.path),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Error banner
          if (state.errorMessage != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: OrbitColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: OrbitColors.error),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: OrbitColors.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      style: const TextStyle(
                        color: OrbitColors.error,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Projects List
          Expanded(
            child: _buildProjectsList(state, controller),
          ),
        ],
      ),
    );
  }

  Widget _buildRootChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? OrbitColors.backgroundDark
                : OrbitColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        selected: isSelected,
        onSelected: (_) => onTap(),
        backgroundColor: OrbitColors.surfaceHighlight,
        selectedColor: OrbitColors.primary,
        checkmarkColor: OrbitColors.backgroundDark,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? OrbitColors.primary : OrbitColors.borderSubtle,
          ),
        ),
      ),
    );
  }

  Widget _buildProjectsList(
    ProjectsState state,
    ProjectsController controller,
  ) {
    if (state.isLoading && state.projects.isEmpty) {
      return const Center(
        child: OrbitLoadingIndicator(size: 40),
      );
    }

    final projects = state.filteredProjects;

    if (projects.isEmpty) {
      return RefreshIndicator(
        color: OrbitColors.primary,
        backgroundColor: OrbitColors.surfaceDark,
        onRefresh: () => controller.refresh(),
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder_off_outlined,
                      color: OrbitColors.textMuted, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    state.searchQuery.isNotEmpty
                        ? 'No projects matching "${state.searchQuery}"'
                        : 'No projects discovered in selected root.',
                    style: const TextStyle(
                      color: OrbitColors.textMuted,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: OrbitColors.primary,
      backgroundColor: OrbitColors.surfaceDark,
      onRefresh: () => controller.refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: projects.length,
        itemBuilder: (context, index) {
          final project = projects[index];
          return ProjectTile(
            project: project,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProjectDetailScreen(
                    projectPath: project.path,
                    projectName: project.name,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
