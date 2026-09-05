import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:orbit_mobile/core/providers.dart';
import 'package:orbit_mobile/features/ai/controllers/ai_task_controller.dart';
import 'package:orbit_mobile/features/ai/views/ai_command_center_screen.dart';
import 'package:orbit_mobile/protocol/models/ai_context.dart';
import 'package:orbit_mobile/protocol/models/file_models.dart';
import 'package:orbit_mobile/shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';

class MarkdownViewerScreen extends ConsumerStatefulWidget {
  final String path;
  final String fileName;

  const MarkdownViewerScreen({
    super.key,
    required this.path,
    required this.fileName,
  });

  @override
  ConsumerState<MarkdownViewerScreen> createState() => _MarkdownViewerScreenState();
}

class _MarkdownViewerScreenState extends ConsumerState<MarkdownViewerScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  String _content = '';
  bool _showSource = false;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = ref.read(webSocketClientProvider);
      final res = await client.sendRequest('files.read', payload: {'path': widget.path});
      if (res.success && res.payload != null) {
        final readRes = FileReadResponse.fromJson(res.payload!);
        if (mounted) {
          setState(() {
            _content = readRes.content;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = res.error?.message ?? 'Failed to read Markdown file';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _copyAll() {
    Clipboard.setData(ClipboardData(text: _content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Markdown copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _askOrbitAi() {
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
          initialPrompt: 'Review ${widget.fileName}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OrbitColors.orbitBackground,
      appBar: AppBar(
        backgroundColor: OrbitColors.orbitSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: OrbitColors.orbitTextPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    widget.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: OrbitColors.orbitTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: OrbitColors.orbitAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: OrbitColors.orbitAccent.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: const Text(
                    'MARKDOWN',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: OrbitColors.orbitAccent,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              widget.path,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: OrbitColors.orbitTextMuted,
              ),
            ),
          ],
        ),
        actions: [
          // Ask Orbit AI
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: OrbitColors.orbitAccent, size: 20),
            tooltip: 'Ask Orbit AI',
            onPressed: _askOrbitAi,
          ),
          // Copy
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: OrbitColors.orbitTextSecondary, size: 18),
            tooltip: 'Copy all',
            onPressed: _copyAll,
          ),
        ],
      ),
      body: Column(
        children: [
          // Segmented Toggle: [ Preview ] [ Source ]
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0C1019),
              border: Border(
                bottom: BorderSide(color: OrbitColors.orbitBorder, width: 0.8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: OrbitColors.orbitBackground,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: OrbitColors.orbitBorder, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildToggleButton(
                        label: 'Preview',
                        icon: Icons.visibility_outlined,
                        isActive: !_showSource,
                        onTap: () => setState(() => _showSource = false),
                      ),
                      _buildToggleButton(
                        label: 'Source',
                        icon: Icons.code_rounded,
                        isActive: _showSource,
                        onTap: () => setState(() => _showSource = true),
                      ),
                    ],
                  ),
                ),
                Text(
                  _showSource ? 'Raw text' : 'Rendered view',
                  style: const TextStyle(
                    fontSize: 11,
                    color: OrbitColors.orbitTextMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          // Main View Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: OrbitLoadingIndicator(size: 40),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: OrbitColors.orbitError, size: 36),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: OrbitColors.orbitError,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: OrbitColors.orbitAccent,
                                  side: const BorderSide(color: OrbitColors.orbitAccent),
                                ),
                                onPressed: _loadFile,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _showSource
                        ? _buildSourceView()
                        : _buildMarkdownPreview(),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? OrbitColors.orbitSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isActive ? OrbitColors.orbitAccent : OrbitColors.orbitTextMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? OrbitColors.orbitTextPrimary : OrbitColors.orbitTextMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceView() {
    return Container(
      color: const Color(0xFF070A10),
      width: double.infinity,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _content,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.6,
            color: Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }

  Widget _buildMarkdownPreview() {
    return Markdown(
      data: _content,
      selectable: true,
      padding: const EdgeInsets.all(20),
      onTapLink: (text, href, title) {
        if (href != null && href.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Link: $href'),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Copy',
                textColor: OrbitColors.orbitAccent,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: href));
                },
              ),
            ),
          );
        }
      },
      builders: {
        'code': MobileMarkdownCodeBuilder(context),
      },
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(
          color: Color(0xFFD1D5DB),
          fontSize: 13,
          height: 1.6,
        ),
        h1: const TextStyle(
          color: OrbitColors.orbitTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          height: 1.3,
        ),
        h2: const TextStyle(
          color: OrbitColors.orbitTextPrimary,
          fontSize: 17,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.3,
          height: 1.3,
        ),
        h3: const TextStyle(
          color: OrbitColors.orbitTextPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        h4: const TextStyle(
          color: OrbitColors.orbitTextPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        blockquote: const TextStyle(
          color: OrbitColors.orbitTextSecondary,
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(4),
          border: const Border(
            left: BorderSide(color: OrbitColors.accentCyan, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        code: const TextStyle(
          backgroundColor: Colors.transparent,
          color: OrbitColors.accentCyan,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFF06090F),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: OrbitColors.orbitBorder),
        ),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: OrbitColors.orbitBorder, width: 1),
          ),
        ),
        tableBorder: TableBorder.all(color: OrbitColors.orbitBorder, width: 0.8),
        tableHead: const TextStyle(
          color: OrbitColors.orbitTextPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        tableBody: const TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 12,
        ),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        listBullet: const TextStyle(
          color: OrbitColors.orbitAccent,
          fontWeight: FontWeight.bold,
        ),
        a: const TextStyle(
          color: OrbitColors.accentCyan,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

class MobileMarkdownCodeBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  MobileMarkdownCodeBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    final isMultiLine = text.contains('\n');
    final classAttr = element.attributes['class'] ?? '';
    final isBlock = isMultiLine || classAttr.isNotEmpty;

    if (!isBlock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const BorderSide(color: Color(0x1FFFFFFF)).color),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11.5,
            color: OrbitColors.accentCyan,
          ),
        ),
      );
    }

    String lang = '';
    if (classAttr.startsWith('language-')) {
      lang = classAttr.replaceFirst('language-', '');
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF06090F),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: OrbitColors.orbitBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF0D121F),
              borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
              border: Border(bottom: BorderSide(color: OrbitColors.orbitBorder)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lang.isNotEmpty ? lang.toUpperCase() : 'CODE',
                  style: const TextStyle(
                    color: OrbitColors.orbitTextMuted,
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code snippet copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.copy_rounded, size: 11, color: OrbitColors.orbitTextMuted),
                        SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(
                            color: OrbitColors.orbitTextMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFE2E8F0),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
