import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit_mobile/core/providers.dart';
import 'package:orbit_mobile/protocol/models/file_models.dart';
import 'package:orbit_mobile/shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';

class TextFileEditorScreen extends ConsumerStatefulWidget {
  final String path;
  final String fileName;

  const TextFileEditorScreen({
    super.key,
    required this.path,
    required this.fileName,
  });

  @override
  ConsumerState<TextFileEditorScreen> createState() =>
      _TextFileEditorScreenState();
}

class _TextFileEditorScreenState extends ConsumerState<TextFileEditorScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String _initialContent = '';
  int _fileSize = 0;

  bool get _hasUnsavedChanges => _textController.text != _initialContent;

  String get _formattedSize {
    if (_fileSize < 1024) return '$_fileSize B';
    return '${(_fileSize / 1024).toStringAsFixed(1)} KB';
  }

  @override
  void initState() {
    super.initState();
    _loadFileContent();
    _textController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
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
        _fileSize = content.length;
        setState(() {
          _isSaving = false;
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
          'You have unsaved edits. Are you sure you want to discard them?',
          style: TextStyle(color: OrbitColors.orbitTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: OrbitColors.orbitTextMuted)),
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
                  Text(
                    widget.fileName,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: OrbitColors.orbitTextPrimary,
                    ),
                  ),
                  if (_hasUnsavedChanges) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: OrbitColors.orbitAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                _fileSize > 0 ? '${widget.path} • $_formattedSize' : widget.path,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: OrbitColors.orbitTextMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
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
                        foregroundColor: _hasUnsavedChanges
                            ? Colors.black
                            : OrbitColors.orbitTextMuted,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        elevation: 0,
                      ),
                      onPressed: _hasUnsavedChanges ? _saveFileContent : null,
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text(
                        'Save',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
            ),
          ],
        ),
        body: _isLoading
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
                : TextField(
                    controller: _textController,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: OrbitColors.orbitTextPrimary,
                      height: 1.4,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
      ),
    );
  }
}
