import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import '../../../shared/theme/orbit_colors.dart';

class CodeElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  CodeElementBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    final isMultiLine = text.contains('\n');
    final classAttr = element.attributes['class'] ?? '';
    final isBlock = isMultiLine || classAttr.isNotEmpty;

    if (!isBlock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: OrbitColors.surfaceDark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: OrbitColors.borderSubtle),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
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
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: OrbitColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF0D1117),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              border: Border(bottom: BorderSide(color: OrbitColors.borderSubtle)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lang.isNotEmpty ? lang.toUpperCase() : 'CODE',
                  style: const TextStyle(
                    color: OrbitColors.textMuted,
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
                        content: Text('Code copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.copy, size: 12, color: OrbitColors.textMuted),
                        SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(
                            color: OrbitColors.textMuted,
                            fontSize: 11,
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
            child: SelectableText(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFE6EDF3),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AiResponseMarkdown extends StatelessWidget {
  final String text;

  const AiResponseMarkdown({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return MarkdownBody(
      data: text,
      selectable: true,
      builders: {
        'code': CodeElementBuilder(context),
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: const TextStyle(
          color: OrbitColors.textPrimary,
          fontSize: 13,
          height: 1.5,
        ),
        h1: const TextStyle(
          color: OrbitColors.accentCyan,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          height: 1.4,
        ),
        h2: const TextStyle(
          color: OrbitColors.accentCyan,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          height: 1.4,
        ),
        h3: const TextStyle(
          color: OrbitColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          height: 1.4,
        ),
        listBullet: const TextStyle(
          color: OrbitColors.primary,
          fontSize: 13,
        ),
        blockquote: const TextStyle(
          color: OrbitColors.textMuted,
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: const Border(
            left: BorderSide(color: OrbitColors.primary, width: 3),
          ),
          color: OrbitColors.surfaceDark.withOpacity(0.5),
        ),
      ),
    );
  }
}
