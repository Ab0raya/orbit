import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit_mobile/features/files/controllers/file_explorer_controller.dart';
import 'package:orbit_mobile/features/files/views/code_editor_screen.dart';
import 'package:orbit_mobile/features/files/views/image_preview_screen.dart';
import 'package:orbit_mobile/features/files/views/binary_file_screen.dart';
import 'package:orbit_mobile/features/files/views/markdown_viewer_screen.dart';
import 'package:orbit_mobile/features/files/widgets/file_entry_tile.dart';
import 'package:orbit_mobile/features/files/widgets/file_path_bar.dart';
import 'package:orbit_mobile/protocol/models/file_models.dart';
import 'package:orbit_mobile/shared/theme/orbit_colors.dart';

import '../../../shared/widgets/orbit_loading_indicator.dart';

class FileExplorerScreen extends ConsumerStatefulWidget {
  final String? initialPath;
  final VoidCallback? onBack;

  const FileExplorerScreen({
    super.key,
    this.initialPath,
    this.onBack,
  });

  @override
  ConsumerState<FileExplorerScreen> createState() => _FileExplorerScreenState();
}

class _FileExplorerScreenState extends ConsumerState<FileExplorerScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(fileExplorerControllerProvider.notifier)
            .openDirectory(widget.initialPath!);
      });
    }
  }

  void _openFile(String path, String name) {
    final category = FileCategory.fromExtension(name);
    Widget destination;
    switch (category) {
      case FileCategory.markdown:
        destination = MarkdownViewerScreen(path: path, fileName: name);
        break;
      case FileCategory.image:
        destination = ImagePreviewScreen(path: path, fileName: name);
        break;
      case FileCategory.code:
      case FileCategory.text:
        destination = CodeEditorScreen(path: path, fileName: name);
        break;
      case FileCategory.binary:
        destination = BinaryFileScreen(path: path, fileName: name);
        break;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => destination));
  }

  void _openSearchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: OrbitColors.orbitBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => _FileSearchSheet(
        onSelectFile: (path, name) {
          Navigator.of(ctx).pop();
          _openFile(path, name);
        },
      ),
    );
  }

  Future<void> _promptCreateFolder() async {
    final textController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OrbitColors.orbitCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: OrbitColors.orbitBorder),
        ),
        title: const Text(
          'Create New Folder',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: textController,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Folder name',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF141414),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: OrbitColors.orbitBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: OrbitColors.orbitAccentCyan),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a folder name';
              }
              if (value.contains('/') || value.contains('\\')) {
                return 'Name cannot contain / or \\';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: OrbitColors.orbitAccentCyan,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final success = await ref
                    .read(fileExplorerControllerProvider.notifier)
                    .createDirectory(textController.text.trim());
                if (ctx.mounted) {
                  Navigator.of(ctx).pop(success);
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Folder created successfully'),
          backgroundColor: OrbitColors.orbitCard,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _promptDelete(FileEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OrbitColors.orbitCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: OrbitColors.orbitBorder),
        ),
        title: Text(
          'Delete ${entry.isDirectory ? "Folder" : "File"}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to permanently delete "${entry.name}"? This action cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final success = await ref
                  .read(fileExplorerControllerProvider.notifier)
                  .deleteEntry(entry.path);
              if (mounted && success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted "${entry.name}"'),
                    backgroundColor: OrbitColors.orbitCard,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _promptRename(FileEntry entry) {
    final textController = TextEditingController(text: entry.name);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OrbitColors.orbitCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: OrbitColors.orbitBorder),
        ),
        title: Text(
          'Rename ${entry.isDirectory ? "Folder" : "File"}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: textController,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'New name',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF141414),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: OrbitColors.orbitBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: OrbitColors.orbitAccentCyan),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a name';
              }
              if (value.contains('/') || value.contains('\\')) {
                return 'Name cannot contain / or \\';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: OrbitColors.orbitAccentCyan,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final newName = textController.text.trim();
                Navigator.of(ctx).pop();
                final success = await ref
                    .read(fileExplorerControllerProvider.notifier)
                    .renameEntry(entry.path, newName);
                if (mounted && success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Renamed to "$newName"'),
                      backgroundColor: OrbitColors.orbitCard,
                    ),
                  );
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _copyPath(String path, {bool isDirectory = false}) {
    Clipboard.setData(ClipboardData(text: path));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
              color: OrbitColors.orbitAccentCyan,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Copied to clipboard: $path',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: OrbitColors.orbitCard,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: OrbitColors.orbitBorder),
        ),
      ),
    );
  }

  Widget _buildHiddenFilesToggle(bool showHidden) {
    return Tooltip(
      message: showHidden ? 'Hide hidden files' : 'Show hidden files',
      child: InkWell(
        key: const Key('toggle_show_hidden_files'),
        onTap: () {
          ref.read(showHiddenFilesProvider.notifier).toggle();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: showHidden
                  ? OrbitColors.orbitTextMuted
                  : OrbitColors.orbitBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 14,
                color: showHidden
                    ? OrbitColors.orbitTextPrimary
                    : OrbitColors.orbitTextMuted,
              ),
              const SizedBox(width: 5),
              Text(
                'Hidden',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: showHidden
                      ? OrbitColors.orbitTextPrimary
                      : OrbitColors.orbitTextMuted,
                ),
              ),
              const SizedBox(width: 5),
              SizedBox(
                height: 18,
                width: 26,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Switch(
                    key: const Key('switch_show_hidden_files'),
                    value: showHidden,
                    onChanged: (val) {
                      ref
                          .read(showHiddenFilesProvider.notifier)
                          .setShowHiddenFiles(val);
                    },
                    activeColor: OrbitColors.orbitTextPrimary,
                    activeTrackColor: const Color(0xFF383838),
                    inactiveThumbColor: OrbitColors.orbitTextMuted,
                    inactiveTrackColor: const Color(0xFF1E1E1E),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fileExplorerControllerProvider);
    final notifier = ref.read(fileExplorerControllerProvider.notifier);
    final showHidden = ref.watch(showHiddenFilesProvider);
    final canPopRoute = Navigator.of(context).canPop();
    final showLeading = widget.onBack != null || canPopRoute || state.history.length > 1;

    return PopScope(
      canPop: !canPopRoute && widget.onBack == null ? (state.history.length <= 1) : false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (state.history.length > 1) {
          notifier.navigateUp();
        } else if (canPopRoute) {
          Navigator.of(context).pop();
        } else if (widget.onBack != null) {
          widget.onBack!();
        }
      },
      child: Scaffold(
        backgroundColor: OrbitColors.orbitBackground,
        appBar: AppBar(
          backgroundColor: OrbitColors.orbitSurface,
          elevation: 0,
          leading: showLeading
              ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  tooltip: 'Back',
                  onPressed: () {
                    if (canPopRoute) {
                      Navigator.of(context).pop();
                    } else if (state.history.length > 1) {
                      notifier.navigateUp();
                    } else if (widget.onBack != null) {
                      widget.onBack!();
                    }
                  },
                )
              : null,
          title: const Text(
            'ORBIT / FILES',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.white,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white, size: 20),
              tooltip: 'Search files',
              onPressed: _openSearchDialog,
            ),
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white, size: 22),
              tooltip: 'New folder',
              onPressed: _promptCreateFolder,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            FilePathBar(
              currentPath: state.currentPath,
              onNavigateUp: () => notifier.navigateUp(),
              onGoHome: () => notifier.goHome(),
              onRefresh: () => notifier.refresh(),
              onCreateFolder: _promptCreateFolder,
              onCopyPath: () => _copyPath(state.currentPath, isDirectory: true),
            ),
            // Inline Search Bar with compact Show Hidden Files toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _openSearchDialog,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0F0F),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: OrbitColors.orbitBorder),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 16,
                              color: OrbitColors.orbitTextMuted,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Search files and directories...',
                                style: TextStyle(
                                  color: OrbitColors.orbitTextMuted,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildHiddenFilesToggle(showHidden),
                ],
              ),
            ),
          if (state.errorMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: OrbitColors.orbitError.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: OrbitColors.orbitError,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: OrbitColors.orbitError,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 14),
                    color: OrbitColors.orbitError,
                    onPressed: () => notifier.refresh(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: state.isLoading && state.entries.isEmpty
                ? const Center(child: OrbitLoadingIndicator(size: 40))
                : state.entries.isEmpty
                ? Center(
                    child: Text(
                      state.isLoading ? 'Loading...' : 'This folder is empty',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: OrbitColors.orbitTextMuted,
                        fontSize: 13,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: OrbitColors.orbitAccent,
                    backgroundColor: OrbitColors.orbitCard,
                    onRefresh: () => notifier.refresh(),
                    child: ListView.builder(
                      itemCount: state.entries.length,
                      itemBuilder: (context, index) {
                        final entry = state.entries[index];
                        return FileEntryTile(
                          entry: entry,
                          onTap: () {
                            if (entry.isDirectory) {
                              notifier.openDirectory(entry.path);
                            } else {
                              _openFile(entry.path, entry.name);
                            }
                          },
                          onRename: () => _promptRename(entry),
                          onDelete: () => _promptDelete(entry),
                          onCopyPath: () => _copyPath(
                            entry.path,
                            isDirectory: entry.isDirectory,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
  }
}

class _FileSearchSheet extends ConsumerStatefulWidget {
  final void Function(String path, String name) onSelectFile;

  const _FileSearchSheet({required this.onSelectFile});

  @override
  ConsumerState<_FileSearchSheet> createState() => _FileSearchSheetState();
}

class _FileSearchSheetState extends ConsumerState<_FileSearchSheet> {
  final _searchController = TextEditingController();
  String _mode = 'name'; // 'name' | 'content'
  bool _isSearching = false;
  FileSearchResult? _results;
  String? _searchError;

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final notifier = ref.read(fileExplorerControllerProvider.notifier);
      final res = await notifier.searchFiles(query, _mode);
      if (mounted) {
        setState(() {
          _results = res;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = e.toString();
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showHidden = ref.watch(showHiddenFilesProvider);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: OrbitColors.orbitBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Title & Mode / Filter Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Search files...',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: OrbitColors.orbitTextPrimary,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mode Toggle: [ Name ] [ Content ]
                    Container(
                      decoration: BoxDecoration(
                        color: OrbitColors.orbitCard,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: OrbitColors.orbitBorder),
                      ),
                      child: Row(
                        children: [
                          _buildModeButton('name', 'Name'),
                          _buildModeButton('content', 'Content'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Hidden toggle in search sheet
                    InkWell(
                      key: const Key('search_toggle_show_hidden_files'),
                      onTap: () {
                        ref.read(showHiddenFilesProvider.notifier).toggle();
                        if (_searchController.text.trim().isNotEmpty) {
                          _performSearch();
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: OrbitColors.orbitCard,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: showHidden
                                ? OrbitColors.orbitTextMuted
                                : OrbitColors.orbitBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 13,
                              color: showHidden
                                  ? OrbitColors.orbitTextPrimary
                                  : OrbitColors.orbitTextMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Hidden',
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: showHidden
                                    ? OrbitColors.orbitTextPrimary
                                    : OrbitColors.orbitTextMuted,
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              height: 14,
                              width: 22,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: Switch(
                                  value: showHidden,
                                  onChanged: (val) {
                                    ref
                                        .read(showHiddenFilesProvider.notifier)
                                        .setShowHiddenFiles(val);
                                    if (_searchController.text.trim().isNotEmpty) {
                                      _performSearch();
                                    }
                                  },
                                  activeColor: OrbitColors.orbitTextPrimary,
                                  activeTrackColor: const Color(0xFF383838),
                                  inactiveThumbColor: OrbitColors.orbitTextMuted,
                                  inactiveTrackColor: const Color(0xFF1E1E1E),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
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

            // Search input box
            Container(
              decoration: BoxDecoration(
                color: OrbitColors.orbitCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: OrbitColors.orbitBorder),
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(
                  color: OrbitColors.orbitTextPrimary,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: _mode == 'name'
                      ? 'Filename or pattern...'
                      : 'Text in files...',
                  hintStyle: const TextStyle(
                    color: OrbitColors.orbitTextMuted,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: OrbitColors.orbitAccent,
                    size: 18,
                  ),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: OrbitColors.orbitAccent,
                            ),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            color: OrbitColors.orbitAccent,
                            size: 18,
                          ),
                          onPressed: _performSearch,
                        ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _performSearch(),
              ),
            ),
            const SizedBox(height: 10),

            // Result summary
            if (_results != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_results!.totalMatches} result${_results!.totalMatches == 1 ? "" : "s"}${_results!.truncated ? " (limit reached)" : ""}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: OrbitColors.orbitTextMuted,
                  ),
                ),
              ),

            // Results List
            Expanded(
              child: _searchError != null
                  ? Center(
                      child: Text(
                        _searchError!,
                        style: const TextStyle(
                          color: OrbitColors.orbitError,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : _results == null
                  ? Center(
                      child: Text(
                        _isSearching
                            ? 'Searching...'
                            : 'Enter a query and tap search',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: OrbitColors.orbitTextMuted,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : _results!.results.isEmpty
                  ? const Center(
                      child: Text(
                        'No matching files found',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: OrbitColors.orbitTextMuted,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results!.results.length,
                      separatorBuilder: (context, index) => const Divider(
                        color: OrbitColors.orbitBorder,
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final item = _results!.results[index];
                        return InkWell(
                          onTap: () =>
                              widget.onSelectFile(item.path, item.name),
                          onLongPress: () {
                            Clipboard.setData(ClipboardData(text: item.path));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Copied path: ${item.path}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                                duration: const Duration(seconds: 2),
                                backgroundColor: OrbitColors.orbitCard,
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      item.isDirectory
                                          ? Icons.folder_outlined
                                          : Icons.insert_drive_file_outlined,
                                      size: 16,
                                      color: item.isDirectory
                                          ? OrbitColors.accentCyan
                                          : OrbitColors.orbitTextSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: OrbitColors.orbitTextPrimary,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.copy_rounded,
                                        size: 14,
                                        color: OrbitColors.orbitTextMuted,
                                      ),
                                      tooltip: 'Copy path',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 24,
                                        minHeight: 24,
                                      ),
                                      onPressed: () {
                                        Clipboard.setData(
                                          ClipboardData(text: item.path),
                                        );
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Copied path: ${item.path}',
                                                  style: const TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                duration: const Duration(
                                                  seconds: 2,
                                                ),
                                                backgroundColor:
                                                    OrbitColors.orbitCard,
                                              ),
                                            );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.path,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    color: OrbitColors.orbitTextMuted,
                                  ),
                                ),
                                if (item.snippet != null) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0A0F19),
                                      borderRadius: BorderRadius.circular(4),
                                      border: const Border(
                                        left: BorderSide(
                                          color: OrbitColors.accentCyan,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (item.line != null) ...[
                                          Text(
                                            '${item.line}: ',
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                              color: OrbitColors.accentCyan,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                        Expanded(
                                          child: Text(
                                            item.snippet!.trim(),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                              color: Color(0xFFCBD5E1),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(String modeKey, String label) {
    final isSelected = _mode == modeKey;
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: () {
        setState(() {
          _mode = modeKey;
        });
        if (_searchController.text.trim().isNotEmpty) {
          _performSearch();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? OrbitColors.orbitSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? OrbitColors.accentCyan
                : OrbitColors.orbitTextMuted,
          ),
        ),
      ),
    );
  }
}
