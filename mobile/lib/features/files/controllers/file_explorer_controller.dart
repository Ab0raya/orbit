import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit_mobile/core/networking/orbit_websocket_client.dart';
import 'package:orbit_mobile/core/providers.dart';
import 'package:orbit_mobile/core/storage/local_storage.dart';
import 'package:orbit_mobile/protocol/models/file_models.dart';

bool isHiddenEntryName(String name) {
  return name.startsWith('.') && name != '.' && name != '..';
}

bool isSearchResultHidden(SearchFileResult item, {String? searchRoot}) {
  if (isHiddenEntryName(item.name)) return true;
  String rel = item.path;
  if (searchRoot != null && searchRoot.isNotEmpty && rel.startsWith(searchRoot)) {
    rel = rel.substring(searchRoot.length);
  }
  final segments = rel.split(RegExp(r'[/\\]'));
  for (final seg in segments) {
    if (isHiddenEntryName(seg)) return true;
  }
  return false;
}

class FileExplorerState {
  final String currentPath;
  final List<FileRoot> roots;
  final List<FileEntry> rawEntries;
  final bool showHiddenFiles;
  final bool isLoading;
  final String? errorMessage;
  final List<String> history;

  const FileExplorerState({
    this.currentPath = '',
    this.roots = const [],
    List<FileEntry> entries = const [],
    List<FileEntry>? rawEntries,
    this.showHiddenFiles = false,
    this.isLoading = false,
    this.errorMessage,
    this.history = const [],
  }) : rawEntries = rawEntries ?? entries;

  List<FileEntry> get entries {
    final filteredDots =
        rawEntries.where((e) => e.name != '.' && e.name != '..');
    if (showHiddenFiles) {
      return filteredDots.toList();
    }
    return filteredDots.where((e) => !isHiddenEntryName(e.name)).toList();
  }

  FileExplorerState copyWith({
    String? currentPath,
    List<FileRoot>? roots,
    List<FileEntry>? rawEntries,
    List<FileEntry>? entries,
    bool? showHiddenFiles,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    List<String>? history,
  }) {
    return FileExplorerState(
      currentPath: currentPath ?? this.currentPath,
      roots: roots ?? this.roots,
      rawEntries: rawEntries ?? entries ?? this.rawEntries,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      history: history ?? this.history,
    );
  }
}

final showHiddenFilesProvider =
    StateNotifierProvider<ShowHiddenFilesNotifier, bool>((ref) {
  ILocalStorage? storage;
  try {
    storage = ref.watch(localStorageProvider);
  } catch (_) {
    storage = null;
  }
  return ShowHiddenFilesNotifier(storage);
});

class ShowHiddenFilesNotifier extends StateNotifier<bool> {
  final ILocalStorage? _storage;
  bool _hasUserChanged = false;

  ShowHiddenFilesNotifier(this._storage) : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    if (_storage != null) {
      final show = await _storage.getShowHiddenFiles();
      if (!_hasUserChanged && mounted) {
        state = show;
      }
    }
  }

  Future<void> toggle() => setShowHiddenFiles(!state);

  Future<void> setShowHiddenFiles(bool value) async {
    _hasUserChanged = true;
    state = value;
    if (_storage != null) {
      await _storage.saveShowHiddenFiles(value);
    }
  }
}

class FileExplorerController extends StateNotifier<FileExplorerState> {
  final OrbitWebSocketClient _client;

  FileExplorerController(this._client, {bool showHidden = false})
      : super(FileExplorerState(showHiddenFiles: showHidden)) {
    initialize();
  }

  void setShowHiddenFiles(bool value) {
    state = state.copyWith(showHiddenFiles: value);
  }

  void toggleShowHiddenFiles() {
    setShowHiddenFiles(!state.showHiddenFiles);
  }

  Future<void> initialize({bool openFirstRoot = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _client.sendRequest('files.roots');
      if (res.success && res.payload != null) {
        final rawRoots = res.payload!['roots'] as List<dynamic>? ?? [];
        final roots = rawRoots
            .map((r) => FileRoot.fromJson(r as Map<String, dynamic>))
            .toList();

        state = state.copyWith(roots: roots);

        if (openFirstRoot && roots.isNotEmpty) {
          await openDirectory(roots.first.path, addToHistory: true);
        } else {
          state = state.copyWith(
            currentPath: '',
            entries: [],
            rawEntries: [],
            isLoading: false,
            history: const [''],
            clearError: true,
          );
        }
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.error?.message ?? 'Failed to load browse roots',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> openLocations({bool addToHistory = true}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _client.sendRequest('files.roots');
      if (res.success && res.payload != null) {
        final rawRoots = res.payload!['roots'] as List<dynamic>? ?? [];
        final roots = rawRoots
            .map((r) => FileRoot.fromJson(r as Map<String, dynamic>))
            .toList();

        final updatedHistory = List<String>.from(state.history);
        if (addToHistory && (updatedHistory.isEmpty || updatedHistory.last.isNotEmpty)) {
          updatedHistory.add('');
        }

        state = state.copyWith(
          currentPath: '',
          roots: roots,
          entries: [],
          rawEntries: [],
          isLoading: false,
          history: updatedHistory,
          clearError: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.error?.message ?? 'Failed to load browse roots',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> openDirectory(String path, {bool addToHistory = true}) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final res = await _client.sendRequest('files.list', payload: {'path': path});
      if (res.success && res.payload != null) {
        final listRes = FileListResponse.fromJson(res.payload!);
        final updatedHistory = List<String>.from(state.history);
        if (addToHistory && (updatedHistory.isEmpty || updatedHistory.last != listRes.path)) {
          updatedHistory.add(listRes.path);
        }

        state = state.copyWith(
          currentPath: listRes.path,
          entries: listRes.entries,
          isLoading: false,
          history: updatedHistory,
          clearError: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.error?.message ?? 'Failed to list directory contents',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> navigateUp() async {
    final current = state.currentPath.trim();
    if (current.isEmpty) return;

    // If at root of a drive or filesystem, navigate to LOCATIONS
    final isRoot = current == '/' ||
        RegExp(r'^[a-zA-Z]:[/\\]?$').hasMatch(current) ||
        state.roots.any((r) =>
            r.path == current ||
            '${r.path}/' == current ||
            '${r.path}\\' == current);

    if (isRoot) {
      await openLocations(addToHistory: true);
      return;
    }

    // Determine parent path
    String parent;
    if (current.contains('\\')) {
      final lastBackslash = current.lastIndexOf('\\');
      if (lastBackslash > 0) {
        parent = current.substring(0, lastBackslash);
        if (RegExp(r'^[a-zA-Z]:$').hasMatch(parent)) {
          parent = '$parent\\';
        }
      } else {
        parent = '';
      }
    } else if (current.contains('/')) {
      final lastSlash = current.lastIndexOf('/');
      if (lastSlash == 0) {
        parent = '/';
      } else if (lastSlash > 0) {
        parent = current.substring(0, lastSlash);
        if (RegExp(r'^[a-zA-Z]:$').hasMatch(parent)) {
          parent = '$parent/';
        }
      } else {
        parent = '';
      }
    } else {
      parent = '';
    }

    if (parent.isEmpty) {
      await openLocations(addToHistory: true);
    } else if (parent != current) {
      await openDirectory(parent, addToHistory: true);
    }
  }

  Future<void> goHome() async {
    await openLocations(addToHistory: true);
  }

  Future<void> refresh() async {
    if (state.currentPath.isNotEmpty) {
      await openDirectory(state.currentPath, addToHistory: false);
    } else {
      await openLocations(addToHistory: false);
    }
  }

  Future<bool> createDirectory(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return false;

    final sep = state.currentPath.contains('\\') ? '\\' : '/';
    final targetPath = state.currentPath.endsWith(sep)
        ? '${state.currentPath}$cleanName'
        : '${state.currentPath}$sep$cleanName';

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _client.sendRequest('files.mkdir', payload: {'path': targetPath});
      if (res.success) {
        await refresh();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.error?.message ?? 'Failed to create directory',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> rename(String from, String to) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _client.sendRequest('files.rename', payload: {
        'from': from,
        'to': to,
      });
      if (res.success) {
        await refresh();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.error?.message ?? 'Failed to rename',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> delete(String path) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _client.sendRequest('files.delete', payload: {'path': path});
      if (res.success) {
        await refresh();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.error?.message ?? 'Failed to delete',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> deleteEntry(String path) => delete(path);

  Future<bool> renameEntry(String path, String newName) {
    final separator = path.contains('\\') ? '\\' : '/';
    final lastIndex = path.lastIndexOf(separator);
    final parent = lastIndex >= 0 ? path.substring(0, lastIndex) : '';
    final newPath = parent.isEmpty ? newName : '$parent$separator$newName';
    return rename(path, newPath);
  }

  Future<FileSearchResult?> searchFiles(
    String query,
    String mode, {
    int maxResults = 50,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;

    final root = state.currentPath;
    try {
      final res = await _client.sendRequest('files.search', payload: {
        'root': root,
        'query': cleanQuery,
        'mode': mode,
        'maxResults': maxResults,
      });

      if (res.success && res.payload != null) {
        final result = FileSearchResult.fromJson(res.payload!);
        if (!state.showHiddenFiles) {
          final filtered = result.results.where((item) {
            return !isSearchResultHidden(item, searchRoot: result.root);
          }).toList();

          return FileSearchResult(
            root: result.root,
            query: result.query,
            mode: result.mode,
            totalMatches: filtered.length,
            truncated: result.truncated,
            results: filtered,
          );
        }
        return result;
      } else {
        state = state.copyWith(
          errorMessage: res.error?.message ?? 'Search failed',
        );
        return null;
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return null;
    }
  }
}

final fileExplorerControllerProvider = StateNotifierProvider.autoDispose<
    FileExplorerController, FileExplorerState>((ref) {
  final client = ref.watch(webSocketClientProvider);
  final initialShowHidden = ref.read(showHiddenFilesProvider);
  final controller =
      FileExplorerController(client, showHidden: initialShowHidden);

  ref.listen<bool>(showHiddenFilesProvider, (previous, next) {
    controller.setShowHiddenFiles(next);
  }, fireImmediately: false);

  return controller;
});
