import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/orbit_websocket_client.dart';
import '../../../core/providers.dart';
import '../models/project_models.dart';

class ProjectDetailState {
  final bool isLoading;
  final ProjectInfo? project;
  final GitBranches? branches;
  final Set<String> selectedStaged;
  final Set<String> selectedUnstaged;
  final Set<String> selectedUntracked;
  final bool isCommitting;
  final bool isSwitchingBranch;
  final String? errorMessage;
  final String? successMessage;

  const ProjectDetailState({
    this.isLoading = false,
    this.project,
    this.branches,
    this.selectedStaged = const {},
    this.selectedUnstaged = const {},
    this.selectedUntracked = const {},
    this.isCommitting = false,
    this.isSwitchingBranch = false,
    this.errorMessage,
    this.successMessage,
  });

  ProjectDetailState copyWith({
    bool? isLoading,
    ProjectInfo? project,
    GitBranches? branches,
    Set<String>? selectedStaged,
    Set<String>? selectedUnstaged,
    Set<String>? selectedUntracked,
    bool? isCommitting,
    bool? isSwitchingBranch,
    String? errorMessage,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return ProjectDetailState(
      isLoading: isLoading ?? this.isLoading,
      project: project ?? this.project,
      branches: branches ?? this.branches,
      selectedStaged: selectedStaged ?? this.selectedStaged,
      selectedUnstaged: selectedUnstaged ?? this.selectedUnstaged,
      selectedUntracked: selectedUntracked ?? this.selectedUntracked,
      isCommitting: isCommitting ?? this.isCommitting,
      isSwitchingBranch: isSwitchingBranch ?? this.isSwitchingBranch,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }
}

class ProjectController extends StateNotifier<ProjectDetailState> {
  final OrbitWebSocketClient _client;
  final String projectPath;

  ProjectController(this._client, this.projectPath)
      : super(const ProjectDetailState()) {
    loadProject();
  }

  Future<void> loadProject() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _client.sendRequest('projects.info', payload: {
        'path': projectPath,
      });

      if (res.success && res.payload != null) {
        final info = ProjectInfo.fromJson(res.payload!);
        state = state.copyWith(
          isLoading: false,
          project: info,
        );

        if (info.isGit) {
          await loadBranches();
        }
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.error?.message ?? 'Failed to load project details',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error loading project: $e',
      );
    }
  }

  Future<void> refreshGitStatus() async {
    if (state.project == null || !state.project!.isGit) return;

    try {
      final res = await _client.sendRequest('git.status', payload: {
        'path': projectPath,
      });

      if (res.success && res.payload != null) {
        final status = GitStatus.fromJson(res.payload!);
        final updatedProject = ProjectInfo(
          name: state.project!.name,
          path: state.project!.path,
          kind: state.project!.kind,
          projectType: state.project!.projectType,
          git: status,
        );

        state = state.copyWith(
          project: updatedProject,
          selectedStaged: {},
          selectedUnstaged: {},
          selectedUntracked: {},
          clearError: true,
        );
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to refresh Git status: $e',
      );
    }
  }

  Future<void> loadBranches() async {
    try {
      final res = await _client.sendRequest('git.branches', payload: {
        'path': projectPath,
      });

      if (res.success && res.payload != null) {
        final branches = GitBranches.fromJson(res.payload!);
        state = state.copyWith(branches: branches);
      }
    } catch (e) {
      // Non-fatal
    }
  }

  Future<bool> checkoutBranch(String branch) async {
    state = state.copyWith(isSwitchingBranch: true, clearError: true);
    try {
      final res = await _client.sendRequest('git.checkout', payload: {
        'path': projectPath,
        'branch': branch,
      });

      if (res.success && res.payload != null) {
        final status = GitStatus.fromJson(res.payload!);
        final updatedProject = ProjectInfo(
          name: state.project!.name,
          path: state.project!.path,
          kind: state.project!.kind,
          projectType: state.project!.projectType,
          git: status,
        );

        state = state.copyWith(
          isSwitchingBranch: false,
          project: updatedProject,
          successMessage: 'Switched to branch "$branch"',
        );
        await loadBranches();
        return true;
      } else {
        state = state.copyWith(
          isSwitchingBranch: false,
          errorMessage: res.error?.message ?? 'Checkout failed',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isSwitchingBranch: false,
        errorMessage: 'Checkout error: $e',
      );
      return false;
    }
  }

  Future<bool> createBranch(String name) async {
    state = state.copyWith(isSwitchingBranch: true, clearError: true);
    try {
      final res = await _client.sendRequest('git.create_branch', payload: {
        'path': projectPath,
        'name': name,
      });

      if (res.success && res.payload != null) {
        final status = GitStatus.fromJson(res.payload!);
        final updatedProject = ProjectInfo(
          name: state.project!.name,
          path: state.project!.path,
          kind: state.project!.kind,
          projectType: state.project!.projectType,
          git: status,
        );

        state = state.copyWith(
          isSwitchingBranch: false,
          project: updatedProject,
          successMessage: 'Created and switched to branch "$name"',
        );
        await loadBranches();
        return true;
      } else {
        state = state.copyWith(
          isSwitchingBranch: false,
          errorMessage: res.error?.message ?? 'Failed to create branch',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isSwitchingBranch: false,
        errorMessage: 'Branch creation error: $e',
      );
      return false;
    }
  }

  void toggleStaged(String path) {
    final next = Set<String>.from(state.selectedStaged);
    if (next.contains(path)) {
      next.remove(path);
    } else {
      next.add(path);
    }
    state = state.copyWith(selectedStaged: next);
  }

  void toggleUnstaged(String path) {
    final next = Set<String>.from(state.selectedUnstaged);
    if (next.contains(path)) {
      next.remove(path);
    } else {
      next.add(path);
    }
    state = state.copyWith(selectedUnstaged: next);
  }

  void toggleUntracked(String path) {
    final next = Set<String>.from(state.selectedUntracked);
    if (next.contains(path)) {
      next.remove(path);
    } else {
      next.add(path);
    }
    state = state.copyWith(selectedUntracked: next);
  }

  Future<void> stageSelected() async {
    final toStage = {...state.selectedUnstaged, ...state.selectedUntracked}.toList();
    if (toStage.isEmpty) return;

    try {
      final res = await _client.sendRequest('git.stage', payload: {
        'path': projectPath,
        'paths': toStage,
      });

      if (res.success && res.payload != null) {
        final status = GitStatus.fromJson(res.payload!);
        final updatedProject = ProjectInfo(
          name: state.project!.name,
          path: state.project!.path,
          kind: state.project!.kind,
          projectType: state.project!.projectType,
          git: status,
        );

        state = state.copyWith(
          project: updatedProject,
          selectedUnstaged: {},
          selectedUntracked: {},
          successMessage: 'Staged ${toStage.length} item(s)',
        );
      } else {
        state = state.copyWith(
          errorMessage: res.error?.message ?? 'Failed to stage files',
        );
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Staging error: $e',
      );
    }
  }

  Future<void> unstageSelected() async {
    final toUnstage = state.selectedStaged.toList();
    if (toUnstage.isEmpty) return;

    try {
      final res = await _client.sendRequest('git.unstage', payload: {
        'path': projectPath,
        'paths': toUnstage,
      });

      if (res.success && res.payload != null) {
        final status = GitStatus.fromJson(res.payload!);
        final updatedProject = ProjectInfo(
          name: state.project!.name,
          path: state.project!.path,
          kind: state.project!.kind,
          projectType: state.project!.projectType,
          git: status,
        );

        state = state.copyWith(
          project: updatedProject,
          selectedStaged: {},
          successMessage: 'Unstaged ${toUnstage.length} item(s)',
        );
      } else {
        state = state.copyWith(
          errorMessage: res.error?.message ?? 'Failed to unstage files',
        );
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Unstaging error: $e',
      );
    }
  }

  Future<bool> commit(String message) async {
    final msg = message.trim();
    if (msg.isEmpty) {
      state = state.copyWith(errorMessage: 'Commit message cannot be empty');
      return false;
    }

    state = state.copyWith(isCommitting: true, clearError: true);
    try {
      final res = await _client.sendRequest('git.commit', payload: {
        'path': projectPath,
        'message': msg,
      });

      if (res.success && res.payload != null) {
        final commitResult = GitCommitResult.fromJson(res.payload!);
        state = state.copyWith(
          isCommitting: false,
          successMessage: 'Committed ${commitResult.hash.substring(0, commitResult.hash.length.clamp(0, 7))}: $msg',
        );
        await refreshGitStatus();
        return true;
      } else {
        state = state.copyWith(
          isCommitting: false,
          errorMessage: res.error?.message ?? 'Commit failed',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isCommitting: false,
        errorMessage: 'Commit error: $e',
      );
      return false;
    }
  }
}

final projectControllerProvider = StateNotifierProvider.autoDispose
    .family<ProjectController, ProjectDetailState, String>((ref, path) {
  final client = ref.watch(orbitClientProvider);
  return ProjectController(client, path);
});
