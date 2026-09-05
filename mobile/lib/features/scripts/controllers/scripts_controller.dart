import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/orbit_websocket_client.dart';
import '../../../core/providers.dart';
import '../../../protocol/models/script_models.dart';

class ScriptsState {
  final bool isLoading;
  final bool isSaving;
  final List<Script> scripts;
  final String searchQuery;
  final String scopeFilter; // 'all', 'global', 'project'
  final String? errorMessage;

  const ScriptsState({
    this.isLoading = false,
    this.isSaving = false,
    this.scripts = const [],
    this.searchQuery = '',
    this.scopeFilter = 'all',
    this.errorMessage,
  });

  List<Script> get filteredScripts {
    return scripts.where((s) {
      if (scopeFilter == 'global' && !s.isGlobal) return false;
      if (scopeFilter == 'project' && s.isGlobal) return false;

      if (searchQuery.trim().isEmpty) return true;
      final q = searchQuery.toLowerCase().trim();
      return s.name.toLowerCase().contains(q) ||
          (s.description != null && s.description!.toLowerCase().contains(q)) ||
          s.content.toLowerCase().contains(q) ||
          (s.workingDirectory != null && s.workingDirectory!.toLowerCase().contains(q));
    }).toList();
  }

  ScriptsState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Script>? scripts,
    String? searchQuery,
    String? scopeFilter,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ScriptsState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      scripts: scripts ?? this.scripts,
      searchQuery: searchQuery ?? this.searchQuery,
      scopeFilter: scopeFilter ?? this.scopeFilter,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ScriptsController extends StateNotifier<ScriptsState> {
  final OrbitWebSocketClient _client;
  final String? projectPath;

  ScriptsController(this._client, {this.projectPath}) : super(const ScriptsState()) {
    loadScripts();
  }

  Future<void> loadScripts() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final Map<String, dynamic> payload = {};
      if (projectPath != null && projectPath!.isNotEmpty) {
        payload['projectPath'] = projectPath;
      }

      final res = await _client.sendRequest('scripts.list', payload: payload);
      if (res.success && res.payload != null) {
        final listJson = res.payload!['scripts'] as List<dynamic>?;
        final scripts = listJson
                ?.map((s) => Script.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [];
        state = state.copyWith(
          isLoading: false,
          scripts: scripts,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.error?.message ?? 'Failed to load scripts',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load scripts: $e',
      );
    }
  }

  Future<bool> saveScript(ScriptInput input) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final res = await _client.sendRequest(
        'scripts.save',
        payload: {'script': input.toJson()},
      );
      if (res.success) {
        state = state.copyWith(isSaving: false);
        await loadScripts();
        return true;
      } else {
        state = state.copyWith(
          isSaving: false,
          errorMessage: res.error?.message ?? 'Failed to save script',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to save script: $e',
      );
      return false;
    }
  }

  Future<bool> deleteScript(String id) async {
    try {
      final res = await _client.sendRequest(
        'scripts.delete',
        payload: {'id': id},
      );
      if (res.success) {
        await loadScripts();
        return true;
      } else {
        state = state.copyWith(
          errorMessage: res.error?.message ?? 'Failed to delete script',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to delete script: $e',
      );
      return false;
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setScopeFilter(String filter) {
    state = state.copyWith(scopeFilter: filter);
  }
}

final scriptsControllerProvider = StateNotifierProvider.autoDispose
    .family<ScriptsController, ScriptsState, String?>((ref, projectPath) {
  final client = ref.watch(webSocketClientProvider);
  return ScriptsController(client, projectPath: projectPath);
});
