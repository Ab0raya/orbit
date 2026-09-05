import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:orbit_mobile/shared/theme/orbit_colors.dart';
import 'package:orbit_mobile/features/ai/controllers/ai_conversation_controller.dart';
import 'package:orbit_mobile/features/ai/controllers/ai_task_controller.dart';
import 'package:orbit_mobile/features/ai/models/ai_conversation_models.dart';
import 'package:orbit_mobile/protocol/models/ai_context.dart';

/// Reformed, ultra-compact and overflow-proof conversation history sheet
/// adhering to Orbit's calm monochrome design principles.
class AiConversationsHistorySheet extends ConsumerStatefulWidget {
  final ValueChanged<AiContext>? onContextSelected;

  const AiConversationsHistorySheet({
    super.key,
    this.onContextSelected,
  });

  static Future<void> show(
    BuildContext context, {
    ValueChanged<AiContext>? onContextSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: OrbitColors.orbitSurface,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: OrbitColors.orbitBorder, width: 0.8),
      ),
      builder: (ctx) => AiConversationsHistorySheet(
        onContextSelected: onContextSelected,
      ),
    );
  }

  @override
  ConsumerState<AiConversationsHistorySheet> createState() =>
      _AiConversationsHistorySheetState();
}

class _AiConversationsHistorySheetState
    extends ConsumerState<AiConversationsHistorySheet> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleDeleteConversation(OrbitConversation conv) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: OrbitColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: OrbitColors.borderSubtle),
        ),
        title: const Text(
          'Delete conversation?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Remove this conversation from history?',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: OrbitColors.orbitTextMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final wasActive = ref
              .read(aiConversationControllerProvider)
              .activeConversation
              ?.summary
              .id ==
          conv.id;
      final success = await ref
          .read(aiConversationControllerProvider.notifier)
          .deleteConversation(conv.id);

      if (mounted) {
        if (success) {
          if (wasActive) {
            ref.read(aiTaskControllerProvider.notifier).clearConversation();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Conversation deleted'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          final err = ref.read(aiConversationControllerProvider).errorMessage ??
              'Unable to delete conversation';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unable to delete conversation: $err'),
              backgroundColor: OrbitColors.orbitError,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleSelectConversation(OrbitConversation conv) async {
    final detail = await ref
        .read(aiConversationControllerProvider.notifier)
        .selectConversation(conv.id);

    if (detail != null && mounted) {
      ref.read(aiTaskControllerProvider.notifier).loadConversationMessages(
            detail.messages,
            openCodeSessionId: detail.summary.openCodeSessionId,
            projectPath: detail.summary.projectPath,
          );

      if (detail.summary.projectPath != null) {
        widget.onContextSelected?.call(
          AiContext(
            source: AiContextSource.project,
            path: detail.summary.projectPath,
            displayName: detail.summary.projectPath!.split('/').last,
          ),
        );
      } else if (detail.summary.directoryPath != null) {
        widget.onContextSelected?.call(
          AiContext(
            source: AiContextSource.directory,
            path: detail.summary.directoryPath,
            displayName: detail.summary.directoryPath!.split('/').last,
          ),
        );
      } else {
        widget.onContextSelected?.call(AiContext.none());
      }
      Navigator.pop(context);
    } else if (mounted) {
      final err = ref.read(aiConversationControllerProvider).errorMessage ??
          'Unable to open conversation';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open conversation: $err'),
          backgroundColor: OrbitColors.orbitError,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final convState = ref.watch(aiConversationControllerProvider);
    final allConversations = convState.conversations;
    final query = _searchCtrl.text.trim().toLowerCase();
    final conversations = query.isEmpty
        ? allConversations
        : allConversations.where((c) {
            return c.title.toLowerCase().contains(query) ||
                (c.projectPath?.toLowerCase().contains(query) ?? false) ||
                (c.modelId?.toLowerCase().contains(query) ?? false);
          }).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.80,
        minChildSize: 0.40,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollCtrl) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: OrbitColors.orbitBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 2. Compact Header Row (Guaranteed zero overflow)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.forum_outlined,
                      size: 15,
                      color: OrbitColors.orbitSilver,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'CONVERSATION HISTORY',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // New Chat Action
                    InkWell(
                      onTap: () {
                        ref
                            .read(aiConversationControllerProvider.notifier)
                            .clearActiveConversation();
                        ref
                            .read(aiTaskControllerProvider.notifier)
                            .clearConversation();
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add,
                              size: 12,
                              color: Colors.black,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'New Chat',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Close button
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.all(4.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: OrbitColors.orbitTextMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Compact Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: OrbitColors.orbitCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: OrbitColors.orbitBorder,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search,
                        size: 15,
                        color: OrbitColors.orbitTextMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search conversations...',
                            hintStyle: TextStyle(
                              color: OrbitColors.orbitTextMuted,
                              fontSize: 12,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (q) {
                            setState(() {});
                            ref
                                .read(
                                  aiConversationControllerProvider.notifier,
                                )
                                .searchConversations(q);
                          },
                        ),
                      ),
                      if (_searchCtrl.text.isNotEmpty)
                        InkWell(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() {});
                            ref
                                .read(
                                  aiConversationControllerProvider.notifier,
                                )
                                .searchConversations('');
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.clear,
                              size: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const Divider(color: OrbitColors.orbitBorder, height: 1),

              // 4. Conversation Items List
              Expanded(
                child: conversations.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _searchCtrl.text.isNotEmpty
                                    ? Icons.search_off
                                    : Icons.forum_outlined,
                                size: 28,
                                color: OrbitColors.orbitTextMuted
                                    .withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchCtrl.text.isNotEmpty
                                    ? 'No conversations match "${_searchCtrl.text}"'
                                    : 'No conversations found',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: OrbitColors.orbitTextMuted,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: conversations.length,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        itemBuilder: (context, index) {
                          final conv = conversations[index];
                          final isSelected =
                              convState.activeConversation?.summary.id ==
                              conv.id;
                          final dateStr = DateFormat('MMM d, HH:mm').format(
                            DateTime.fromMillisecondsSinceEpoch(
                              conv.updatedAt * 1000,
                            ),
                          );

                          String? modelBadgeText;
                          if (conv.modelId != null &&
                              conv.modelId!.isNotEmpty) {
                            final parts = conv.modelId!.split('/');
                            modelBadgeText = parts.last;
                          }

                          String? projectBadgeText;
                          if (conv.projectPath != null &&
                              conv.projectPath!.isNotEmpty) {
                            projectBadgeText =
                                conv.projectPath!.split('/').last;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF27272A)
                                  : OrbitColors.orbitCard,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? OrbitColors.orbitSilver
                                        .withValues(alpha: 0.6)
                                    : OrbitColors.orbitBorder,
                                width: 0.8,
                              ),
                            ),
                            child: InkWell(
                              onTap: () => _handleSelectConversation(conv),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(10, 8, 8, 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Row 1: Active dot (if selected) + Title + Delete
                                    Row(
                                      children: [
                                        if (isSelected) ...[
                                          Container(
                                            width: 6,
                                            height: 6,
                                            margin: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            decoration: const BoxDecoration(
                                              color: OrbitColors.orbitSilver,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ],
                                        Expanded(
                                          child: Text(
                                            conv.title.isEmpty
                                                ? 'Untitled conversation'
                                                : conv.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                  : OrbitColors
                                                      .orbitTextSecondary,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        InkWell(
                                          onTap: () =>
                                              _handleDeleteConversation(conv),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: const Padding(
                                            padding: EdgeInsets.all(3),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 15,
                                              color: OrbitColors.orbitTextMuted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    // Row 2: Metadata (Date + Project badge + Model badge)
                                    Row(
                                      children: [
                                        Text(
                                          dateStr,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 9.5,
                                            color: OrbitColors.orbitTextMuted,
                                          ),
                                        ),
                                        if (projectBadgeText != null) ...[
                                          const SizedBox(width: 6),
                                          Flexible(
                                            flex: 1,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withValues(alpha: 0.05),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.08),
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.folder_outlined,
                                                    size: 9,
                                                    color: OrbitColors
                                                        .orbitTextMuted,
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Flexible(
                                                    child: Text(
                                                      projectBadgeText,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontFamily:
                                                            'monospace',
                                                        fontSize: 9.0,
                                                        color: OrbitColors
                                                            .orbitSilver,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (modelBadgeText != null) ...[
                                          const SizedBox(width: 5),
                                          Flexible(
                                            flex: 1,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withValues(alpha: 0.04),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                modelBadgeText,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 9.0,
                                                  color: OrbitColors
                                                      .orbitTextMuted,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
