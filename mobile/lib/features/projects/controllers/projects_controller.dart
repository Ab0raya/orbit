import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/orbit_websocket_client.dart';
import '../../../core/providers.dart';
import '../models/project_models.dart';

class ProjectsState {
  final bool isLoading;
  final List<ProjectRoot> roots;
  final String? selectedRoot;
  final List<ProjectSummary> projects;
  final String searchQuery;
  final String? errorMessage;

  const ProjectsState({
    this.isLoading = false,
    this.roots = const [],
    this.selectedRoot,
    this.projects = const [],
    this.searchQuery = '',
    this.errorMessage,
  });

  List<ProjectSummary> get filteredProjects {
    if (searchQuery.trim().isEmpty) {
      return projects;
    }
    final q = searchQuery.toLowerCase().trim();
    return projects
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.path.toLowerCase().contains(q) ||
            p.projectType.toLowerCase().contains(q))
        .toList();
  }

  ProjectsState copyWith({
    bool? isLoading,
    List<ProjectRoot>? roots,
    String? selectedRoot,
    bool clearSelectedRoot = false,
    List<ProjectSummary>? projects,
    String? searchQuery,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProjectsState(
      isLoading: isLoading ?? this.isLoading,
      roots: roots ?? this.roots,
      selectedRoot:
          clearSelectedRoot ? null : (selectedRoot ?? this.selectedRoot),
      projects: projects ?? this.projects,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ProjectsController extends StateNotifier<ProjectsState> {
  final OrbitWebSocketClient _client;

  ProjectsController(this._client) : super(const ProjectsState()) {
    initialize();
  }

  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // 1. Fetch project roots
      final rootsRes = await _client.sendRequest('projects.roots');
      List<ProjectRoot> roots = [];
      if (rootsRes.success && rootsRes.payload != null) {
        final rootsJson = rootsRes.payload!['roots'] as List<dynamic>?;
        if (rootsJson != null) {
          roots = rootsJson
              .map((r) => ProjectRoot.fromJson(r as Map<String, dynamic>))
              .toList();
        }
      }

      state = state.copyWith(roots: roots);

      // 2. Fetch projects from default or all
      await loadProjects(roots.isNotEmpty ? roots.first.path : null);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to initialize projects: $e',
      );
    }
  }

  Future<void> loadProjects([String? rootPath]) async {
    state = state.copyWith(
      isLoading: true,
      selectedRoot: rootPath,
      clearError: true,
    );

    try {
      final Map<String, dynamic> payload = {};
      if (rootPath != null && rootPath.isNotEmpty) {
        payload['path'] = rootPath;
      }

      final res = await _client.sendRequest('projects.list', payload: payload);
      if (res.success && res.payload != null) {
        final listJson = res.payload!['projects'] as List<dynamic>?;
        final projects = listJson
                ?.map((p) => ProjectSummary.fromJson(p as Map<String, dynamic>))
                .toList() ??
            [];

        state = state.copyWith(
          isLoading: false,
          projects: projects,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.error?.message ?? 'Failed to load projects list',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error loading projects: $e',
      );
    }
  }

  void selectRoot(String? path) {
    if (state.selectedRoot == path) return;
    loadProjects(path);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> refresh() async {
    await loadProjects(state.selectedRoot);
  }
}

final projectsControllerProvider =
    StateNotifierProvider.autoDispose<ProjectsController, ProjectsState>((ref) {
  final client = ref.watch(orbitClientProvider);
  return ProjectsController(client);
});
