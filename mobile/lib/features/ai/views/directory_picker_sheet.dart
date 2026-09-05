import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_button.dart';
import '../../../protocol/models/file_models.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';

class DirectoryPickerSheet extends ConsumerStatefulWidget {
  final String? initialPath;

  const DirectoryPickerSheet({
    super.key,
    this.initialPath,
  });

  static Future<String?> show(BuildContext context, {String? initialPath}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DirectoryPickerSheet(initialPath: initialPath),
    );
  }

  @override
  ConsumerState<DirectoryPickerSheet> createState() =>
      _DirectoryPickerSheetState();
}

class _DirectoryPickerSheetState extends ConsumerState<DirectoryPickerSheet> {
  String _currentPath = '';
  List<FileEntry> _directories = [];
  List<FileRoot> _roots = [];
  bool _isLoading = false;
  String? _errorMessage;
  final List<String> _navigationHistory = [];

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final client = ref.read(webSocketClientProvider);

    try {
      final rootsRes = await client.sendRequest('files.roots');
      if (rootsRes.success && rootsRes.payload != null) {
        final rawRoots = rootsRes.payload!['roots'] as List<dynamic>? ?? [];
        _roots = rawRoots
            .map((r) => FileRoot.fromJson(r as Map<String, dynamic>))
            .toList();
      }

      String target = widget.initialPath ?? '';
      if (target.isEmpty && _roots.isNotEmpty) {
        target = _roots.first.path;
      }

      await _fetchDirectory(target);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _fetchDirectory(String path, {bool pushHistory = true}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final client = ref.read(webSocketClientProvider);

    try {
      final res = await client.sendRequest('files.list', payload: {'path': path});
      if (res.success && res.payload != null) {
        final listRes = FileListResponse.fromJson(res.payload!);
        final onlyDirs =
            listRes.entries.where((e) => e.isDirectory).toList();

        if (pushHistory &&
            _currentPath.isNotEmpty &&
            _currentPath != listRes.path) {
          _navigationHistory.add(_currentPath);
        }

        setState(() {
          _currentPath = listRes.path;
          _directories = onlyDirs;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = res.error?.message ?? 'Failed to list directory';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _navigateUp() {
    if (_navigationHistory.isNotEmpty) {
      final prev = _navigationHistory.removeLast();
      _fetchDirectory(prev, pushHistory: false);
      return;
    }

    if (_currentPath.isEmpty || _currentPath == '/') return;

    final parts = _currentPath.split('/');
    if (parts.length > 1) {
      parts.removeLast();
      final parent = parts.join('/');
      _fetchDirectory(parent.isEmpty ? '/' : parent, pushHistory: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final height = mediaQuery.size.height * 0.75;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: OrbitColors.surfaceDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: OrbitColors.borderSubtle, width: 1),
          left: BorderSide(color: OrbitColors.borderSubtle, width: 1),
          right: BorderSide(color: OrbitColors.borderSubtle, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: OrbitColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: OrbitColors.textPrimary, size: 20),
                  onPressed: _currentPath.isNotEmpty && _currentPath != '/' ? _navigateUp : null,
                  tooltip: 'Parent directory',
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SELECT WORKING DIRECTORY',
                        style: TextStyle(
                          color: OrbitColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currentPath.isEmpty ? 'Loading...' : _currentPath,
                        style: const TextStyle(
                          color: OrbitColors.primary,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: OrbitColors.textMuted, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Cancel',
                ),
              ],
            ),
          ),

          // Roots / Shortcuts row if available
          if (_roots.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _roots.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final r = _roots[idx];
                  final isCurrent = _currentPath == r.path;
                  return GestureDetector(
                    onTap: () => _fetchDirectory(r.path),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? OrbitColors.primary.withOpacity(0.15)
                            : OrbitColors.orbitCard,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isCurrent ? OrbitColors.primary : OrbitColors.borderSubtle,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.dns_outlined,
                            size: 13,
                            color: isCurrent ? OrbitColors.primary : OrbitColors.textMuted,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            r.name,
                            style: TextStyle(
                              fontSize: 11,
                              color: isCurrent ? OrbitColors.primary : OrbitColors.textPrimary,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          const Divider(color: OrbitColors.borderSubtle, height: 16),

          // Content body
          Expanded(
            child: _buildBody(),
          ),

          // Bottom Action Bar
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + mediaQuery.padding.bottom),
            decoration: const BoxDecoration(
              color: OrbitColors.surfaceDark,
              border: Border(
                top: BorderSide(color: OrbitColors.borderSubtle, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: OrbitColors.textMuted,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: OrbitButton(
                    text: 'Select Directory',
                    icon: const Icon(Icons.check, size: 16),
                    isLoading: _isLoading,
                    onPressed: _currentPath.isNotEmpty
                        ? () => Navigator.of(context).pop(_currentPath)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: OrbitLoadingIndicator(size: 40),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: OrbitColors.error, size: 36),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: OrbitColors.textPrimary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OrbitButton(
                text: 'Retry',
                onPressed: () => _fetchDirectory(_currentPath.isEmpty ? '/' : _currentPath),
              ),
            ],
          ),
        ),
      );
    }

    if (_directories.isEmpty) {
      return const Center(
        child: Text(
          'No subdirectories found',
          style: TextStyle(color: OrbitColors.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _directories.length,
      itemBuilder: (context, index) {
        final dir = _directories[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: OrbitColors.orbitCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: OrbitColors.borderSubtle),
          ),
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              dense: true,
              leading: const Icon(
                Icons.folder,
                color: OrbitColors.primary,
                size: 20,
              ),
              title: Text(
                dir.name,
                style: const TextStyle(
                  color: OrbitColors.textPrimary,
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: OrbitColors.textMuted,
                size: 18,
              ),
              onTap: () => _fetchDirectory(dir.path),
            ),
          ),
        );
      },
    );
  }
}
