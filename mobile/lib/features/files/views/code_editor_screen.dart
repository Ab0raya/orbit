import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit_mobile/core/providers.dart';
import 'package:orbit_mobile/protocol/models/file_models.dart';
import 'package:orbit_mobile/shared/theme/orbit_colors.dart';
import 'package:orbit_mobile/protocol/models/ai_context.dart';
import 'package:orbit_mobile/features/ai/controllers/ai_task_controller.dart';
import 'package:orbit_mobile/features/ai/views/ai_command_center_screen.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';

class CodeEditorScreen extends ConsumerStatefulWidget {
  final String path;
  final String fileName;

  const CodeEditorScreen({
    super.key,
    required this.path,
    required this.fileName,
  });

  @override
  ConsumerState<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends ConsumerState<CodeEditorScreen> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditMode = false;
  bool _isSearchOpen = false;
  String? _errorMessage;
  String _initialContent = '';
  int _fileSize = 0;

  // Search state
  List<int> _matchLineIndices = [];
  int _currentMatchIndex = 0;

  bool get _hasUnsavedChanges => _textController.text != _initialContent;

  String get _formattedSize {
    if (_fileSize < 1024) return '$_fileSize B';
    if (_fileSize < 1024 * 1024) return '${(_fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(_fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get _detectedLanguage {
    final ext = widget.fileName.contains('.')
        ? widget.fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'dart':
        return 'dart';
      case 'ts':
      case 'tsx':
        return 'typescript';
      case 'js':
      case 'jsx':
        return 'javascript';
      case 'rs':
        return 'rust';
      case 'py':
        return 'python';
      case 'json':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'md':
      case 'markdown':
        return 'markdown';
      case 'sh':
      case 'bash':
      case 'zsh':
        return 'bash';
      case 'html':
      case 'htm':
        return 'xml';
      case 'css':
      case 'scss':
        return 'css';
      case 'c':
      case 'h':
        return 'c';
      case 'cpp':
      case 'hpp':
      case 'cc':
        return 'cpp';
      case 'go':
        return 'go';
      case 'java':
        return 'java';
      case 'kt':
      case 'kts':
        return 'kotlin';
      case 'swift':
        return 'swift';
      case 'sql':
        return 'sql';
      case 'toml':
      case 'ini':
        return 'ini';
      case 'xml':
        return 'xml';
      default:
        return 'plaintext';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFileContent();
    _textController.addListener(_onTextChanged);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _searchController.removeListener(_onSearchChanged);
    _textController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _matchLineIndices = [];
        _currentMatchIndex = 0;
      });
      return;
    }

    final lines = _textController.text.split('\n');
    final matches = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().contains(query.toLowerCase())) {
        matches.add(i);
      }
    }

    setState(() {
      _matchLineIndices = matches;
      _currentMatchIndex = matches.isNotEmpty ? 0 : 0;
    });

    _scrollToCurrentMatch();
  }

  void _nextMatch() {
    if (_matchLineIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _matchLineIndices.length;
    });
    _scrollToCurrentMatch();
  }

  void _previousMatch() {
    if (_matchLineIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _matchLineIndices.length) %
          _matchLineIndices.length;
    });
    _scrollToCurrentMatch();
  }

  void _scrollToCurrentMatch() {
    if (_matchLineIndices.isEmpty || !_verticalScrollController.hasClients) return;
    final line = _matchLineIndices[_currentMatchIndex];
    const lineHeight = 18.85;
    final targetOffset = (line * lineHeight).clamp(
      0.0,
      _verticalScrollController.position.maxScrollExtent,
    );
    _verticalScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _loadFileContent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = ref.read(webSocketClientProvider);
      final res = await client.sendRequest('files.read', payload: {'path': widget.path});

      if (!mounted) return;

      if (res.success && res.payload != null) {
        final readRes = FileReadResponse.fromJson(res.payload!);
        _initialContent = readRes.content;
        _fileSize = readRes.size;
        _textController.text = readRes.content;
        setState(() {
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = res.error?.message ?? 'Failed to load file';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _saveFileContent() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final client = ref.read(webSocketClientProvider);
      final content = _textController.text;
      final res = await client.sendRequest('files.write', payload: {
        'path': widget.path,
        'content': content,
      });

      if (!mounted) return;

      if (res.success) {
        _initialContent = content;
        _fileSize = utf8.encode(content).length;
        setState(() {
          _isSaving = false;
          _isEditMode = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File saved successfully'),
            backgroundColor: OrbitColors.orbitAccent,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.error?.message ?? 'Failed to save file'),
            backgroundColor: OrbitColors.orbitError,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: OrbitColors.orbitError,
        ),
      );
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OrbitColors.orbitCard,
        title: const Text(
          'Unsaved Changes',
          style: TextStyle(color: OrbitColors.orbitTextPrimary),
        ),
        content: const Text(
          'You have unsaved edits. Discard changes and leave?',
          style: TextStyle(color: OrbitColors.orbitTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Editing', style: TextStyle(color: OrbitColors.orbitTextMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: OrbitColors.orbitError,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final lines = _textController.text.split('\n');
    final lineCount = lines.isEmpty ? 1 : lines.length;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: OrbitColors.orbitBackground,
        appBar: AppBar(
          backgroundColor: OrbitColors.orbitSurface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: OrbitColors.orbitTextPrimary),
            onPressed: () async {
              if (!_hasUnsavedChanges) {
                Navigator.of(context).pop();
              } else {
                final shouldPop = await _onWillPop();
                if (shouldPop && context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.fileName,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: OrbitColors.orbitTextPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: OrbitColors.orbitCard,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: OrbitColors.orbitBorder),
                    ),
                    child: Text(
                      _detectedLanguage.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        color: OrbitColors.orbitAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_hasUnsavedChanges) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.amberAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                '$_formattedSize • $lineCount lines',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: OrbitColors.orbitTextMuted,
                ),
              ),
            ],
          ),
          actions: [
            // Search toggle
            IconButton(
              icon: Icon(
                _isSearchOpen ? Icons.search_off : Icons.search,
                color: _isSearchOpen ? OrbitColors.orbitAccent : OrbitColors.orbitTextSecondary,
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  _isSearchOpen = !_isSearchOpen;
                  if (_isSearchOpen) {
                    _searchFocusNode.requestFocus();
                  } else {
                    _searchController.clear();
                    _matchLineIndices = [];
                  }
                });
              },
              tooltip: 'Search in file',
            ),

            // Copy file content
            IconButton(
              icon: const Icon(Icons.copy, color: OrbitColors.orbitTextSecondary, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _textController.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('File content copied to clipboard'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              tooltip: 'Copy all',
            ),

            // Ask Orbit AI
            IconButton(
              icon: const Icon(Icons.auto_awesome, color: OrbitColors.orbitAccent, size: 20),
              tooltip: 'Ask Orbit AI',
              onPressed: () {
                final sep = widget.path.contains('\\') ? '\\' : '/';
                final lastSep = widget.path.lastIndexOf(sep);
                final parentDir = lastSep > 0 ? widget.path.substring(0, lastSep) : widget.path;
                final aiContext = AiContext.fromDirectory(parentDir);
                ref.read(aiTaskControllerProvider.notifier).setContext(aiContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AiCommandCenterScreen(
                      initialContext: aiContext,
                      initialPrompt: 'Explain ${widget.fileName}',
                    ),
                  ),
                );
              },
            ),

            // View / Edit Mode Toggle
            if (!_isEditMode)
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: OrbitColors.orbitAccent, size: 20),
                onPressed: () {
                  setState(() {
                    _isEditMode = true;
                  });
                },
                tooltip: 'Edit file',
              )
            else ...[
              // Save button
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _isSaving
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: OrbitColors.orbitAccent,
                          ),
                        ),
                      )
                    : ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _hasUnsavedChanges
                              ? OrbitColors.orbitAccent
                              : OrbitColors.orbitCard,
                          foregroundColor:
                              _hasUnsavedChanges ? Colors.black : OrbitColors.orbitTextMuted,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: _hasUnsavedChanges ? _saveFileContent : null,
                        icon: const Icon(Icons.save_outlined, size: 15),
                        label: const Text(
                          'Save',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.check, color: OrbitColors.orbitAccent, size: 20),
                onPressed: () {
                  setState(() {
                    _isEditMode = false;
                  });
                },
                tooltip: 'View mode',
              ),
            ],
          ],
        ),
        body: Column(
          children: [
            // In-file search bar
            if (_isSearchOpen) _buildSearchBar(),

            // Mode indicator banner
            if (_isEditMode)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                color: Colors.amber.withValues(alpha: 0.12),
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 14, color: Colors.amberAccent),
                    const SizedBox(width: 8),
                    const Text(
                      'EDIT MODE — Tap Save when finished',
                      style: TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Spacer(),
                    if (_hasUnsavedChanges)
                      const Text(
                        'UNSAVED EDITS',
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
              ),

            // Main Editor / Viewer Body
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OrbitLoadingIndicator(size: 40),
                          SizedBox(height: 16),
                          Text(
                            'Loading file...',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: OrbitColors.orbitTextMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline,
                                    size: 48, color: OrbitColors.orbitError),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: OrbitColors.orbitError,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: OrbitColors.orbitCard,
                                    foregroundColor: OrbitColors.orbitTextPrimary,
                                  ),
                                  onPressed: _loadFileContent,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _isEditMode
                          ? _buildEditMode(lines)
                          : _buildViewMode(lines),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: OrbitColors.orbitSurface,
        border: Border(bottom: BorderSide(color: OrbitColors.orbitBorder)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: OrbitColors.orbitTextSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: OrbitColors.orbitTextPrimary,
              ),
              decoration: const InputDecoration(
                hintText: 'Search within file...',
                hintStyle: TextStyle(color: OrbitColors.orbitTextMuted, fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty) ...[
            Text(
              _matchLineIndices.isNotEmpty
                  ? '${_currentMatchIndex + 1} of ${_matchLineIndices.length}'
                  : '0 of 0',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: OrbitColors.orbitTextMuted,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: OrbitColors.orbitTextSecondary,
              onPressed: _previousMatch,
              tooltip: 'Previous match',
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: OrbitColors.orbitTextSecondary,
              onPressed: _nextMatch,
              tooltip: 'Next match',
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: OrbitColors.orbitTextMuted,
            onPressed: () {
              setState(() {
                _isSearchOpen = false;
                _searchController.clear();
                _matchLineIndices = [];
              });
            },
            tooltip: 'Close search',
          ),
        ],
      ),
    );
  }

  Widget _buildViewMode(List<String> lines) {
    return SingleChildScrollView(
      controller: _verticalScrollController,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gutter with line numbers
          _buildGutter(lines.length),

          // Code body with syntax highlighting and horizontal scroll
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: HighlightView(
                _textController.text.isEmpty ? ' ' : _textController.text,
                language: _detectedLanguage,
                theme: atomOneDarkTheme,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                textStyle: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditMode(List<String> lines) {
    return SingleChildScrollView(
      controller: _verticalScrollController,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gutter
          _buildGutter(lines.length),

          // Editable text field
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1200,
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: OrbitColors.orbitTextPrimary,
                    height: 1.45,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGutter(int count) {
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: const BoxDecoration(
        color: OrbitColors.orbitSurface,
        border: Border(right: BorderSide(color: OrbitColors.orbitBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(count, (index) {
          final isMatched = _matchLineIndices.contains(index);
          final isCurrentMatch =
              _matchLineIndices.isNotEmpty && _matchLineIndices[_currentMatchIndex] == index;

          return Container(
            height: 18.85,
            alignment: Alignment.centerRight,
            color: isCurrentMatch
                ? Colors.amberAccent.withValues(alpha: 0.35)
                : isMatched
                    ? Colors.amberAccent.withValues(alpha: 0.15)
                    : Colors.transparent,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: isCurrentMatch
                    ? Colors.amberAccent
                    : isMatched
                        ? Colors.amber
                        : OrbitColors.orbitTextMuted,
                fontWeight: isCurrentMatch ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }),
      ),
    );
  }
}
