import 'package:flutter/material.dart';

import '../../../shared/theme/orbit_colors.dart';
import '../models/ai_conversation_models.dart';

/// Calm, premium AI workspace header: quiet control, not a dashboard.
///
/// Level 1 — identity row (borderless, continuous with the background):
/// [Back] ORBIT AI ● READY · N ACTIVE … [history] [+] [more]
/// Level 2 — the single primary control: a quiet model selector.
/// Uses LayoutBuilder (no fixed widths) so 320–430px never overflows.
class OrbitAiHeader extends StatelessWidget implements PreferredSizeWidget {
  final bool showLeading;
  final VoidCallback? onBack;
  final bool isWorking;
  final int activeTaskCount;
  final bool? isPlan;

  final String? selectedModelId;
  final OrbitModelSummary? selectedModel;
  final bool modelsLoading;
  final String? modelsError;
  final VoidCallback? onOpenModelPicker;

  final VoidCallback onOpenHistory;
  final VoidCallback onNewChat;
  final VoidCallback? onClearConversation;
  final VoidCallback onOpenTasks;
  final bool hasMessages;

  const OrbitAiHeader({
    super.key,
    required this.showLeading,
    this.onBack,
    required this.isWorking,
    required this.activeTaskCount,
    this.isPlan,
    this.selectedModelId,
    this.selectedModel,
    this.modelsLoading = false,
    this.modelsError,
    this.onOpenModelPicker,
    required this.onOpenHistory,
    required this.onNewChat,
    this.onClearConversation,
    required this.onOpenTasks,
    this.hasMessages = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    // Ultra-minimal header (~56px): continuous with scaffold, whitespace over borders.
    return Container(
      color: OrbitColors.orbitBackground,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 360;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  showLeading ? 0 : 12,
                  0,
                  narrow ? 4 : 10,
                  0,
                ),
                child: Row(
                  children: [
                    if (showLeading)
                      _QuietIconButton(
                        icon: Icons.arrow_back,
                        tooltip: 'Back',
                        narrow: narrow,
                        onPressed:
                            onBack ?? () => Navigator.of(context).pop(),
                      ),
                    // Visual anchor: plain glyph + Orbit AI identity
                    Icon(
                      Icons.auto_awesome,
                      size: narrow ? 14 : 15,
                      color: OrbitColors.orbitSilver,
                    ),
                    SizedBox(width: narrow ? 6 : 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            label: 'ORBIT AI COMMAND CENTER',
                            child: Text(
                              'ORBIT AI',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: narrow ? 12 : 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _StatusDot(isWorking: isWorking),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  isWorking ? 'WORKING' : 'READY',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: narrow ? 8.5 : 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.7,
                                    color: isWorking
                                        ? const Color(0xFFFCD34D)
                                        : const Color(0xFF6EE7B7),
                                  ),
                                ),
                              ),
                              if (activeTaskCount > 0) ...[
                                const SizedBox(width: 4),
                                const Text(
                                  '·',
                                  style: TextStyle(
                                    color: OrbitColors.orbitTextMuted,
                                    fontSize: 9,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    narrow ? '$activeTaskCount ACT' : '$activeTaskCount ACTIVE',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: narrow ? 8 : 9,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.5,
                                      color: OrbitColors.orbitTextMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 2),
                    _QuietIconButton(
                      icon: Icons.history,
                      tooltip: 'Conversation history',
                      narrow: narrow,
                      onPressed: onOpenHistory,
                    ),
                    _NewChatButton(onPressed: onNewChat, narrow: narrow),
                    _HeaderOverflowMenu(
                      hasMessages: hasMessages,
                      activeTaskCount: activeTaskCount,
                      onClearConversation: onClearConversation,
                      onOpenTasks: onOpenTasks,
                      narrow: narrow,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A single compact AI control row (~42px):
/// [ Default ▾ ]   [ No context ▾ ]   [ Plan ▾ ]
/// Extreme simplicity: thin subtle borders, dark transparent surfaces,
/// small text, minimal chevron icons.
class AiControlBar extends StatelessWidget {
  final String modelLabel;
  final VoidCallback onOpenModelPicker;
  final String contextLabel;
  final VoidCallback onOpenContextPicker;
  final bool isPlan;
  final VoidCallback onOpenModePicker;

  const AiControlBar({
    super.key,
    required this.modelLabel,
    required this.onOpenModelPicker,
    required this.contextLabel,
    required this.onOpenContextPicker,
    required this.isPlan,
    required this.onOpenModePicker,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isVeryNarrow = constraints.maxWidth < 350;
        final isNarrow = constraints.maxWidth < 410;
        final paddingH = isVeryNarrow ? 6.0 : (isNarrow ? 10.0 : 12.0);
        final gap = isVeryNarrow ? 4.0 : 5.0;

        String? prefix;
        String mainContext = contextLabel;
        if (contextLabel.startsWith('Project: ')) {
          final raw = contextLabel.substring('Project: '.length);
          if (isVeryNarrow) {
            prefix = null;
            mainContext = raw;
          } else if (isNarrow) {
            prefix = 'Proj: ';
            mainContext = raw;
          } else {
            prefix = 'Project: ';
            mainContext = raw;
          }
        } else if (contextLabel.startsWith('Directory: ')) {
          final raw = contextLabel.substring('Directory: '.length);
          if (isVeryNarrow) {
            prefix = null;
            mainContext = raw;
          } else if (isNarrow) {
            prefix = 'Dir: ';
            mainContext = raw;
          } else {
            prefix = 'Directory: ';
            mainContext = raw;
          }
        }

        return Container(
          height: 42,
          padding: EdgeInsets.symmetric(horizontal: paddingH),
          margin: const EdgeInsets.only(top: 2, bottom: 4),
          child: Row(
            children: [
              // 1. Model Selector (Most important control)
              Expanded(
                flex: isVeryNarrow ? 1 : 4,
                child: _PillButton(
                  label: modelLabel,
                  onTap: onOpenModelPicker,
                  narrow: isVeryNarrow,
                  tooltip: 'Select AI model ($modelLabel)',
                  semanticLabel: 'Select AI model, currently $modelLabel',
                ),
              ),
              SizedBox(width: gap),
              // 2. Context Selector
              Expanded(
                flex: isVeryNarrow ? 1 : 4,
                child: _PillButton(
                  prefix: prefix,
                  label: mainContext,
                  onTap: onOpenContextPicker,
                  narrow: isVeryNarrow,
                  tooltip: 'Select working context ($contextLabel)',
                  semanticLabel:
                      'Select working context, currently $contextLabel',
                ),
              ),
              SizedBox(width: gap),
              // 3. Mode Selector (Plan / Build)
              Expanded(
                flex: isVeryNarrow ? 1 : 3,
                child: _PillButton(
                  label: isPlan ? 'Plan' : 'Build',
                  onTap: onOpenModePicker,
                  narrow: isVeryNarrow,
                  tooltip:
                      'Select execution mode (${isPlan ? 'Plan' : 'Build'})',
                  semanticLabel:
                      'Select execution mode, currently ${isPlan ? 'Plan' : 'Build'}',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PillButton extends StatelessWidget {
  final String? prefix;
  final String label;
  final VoidCallback onTap;
  final String tooltip;
  final String semanticLabel;
  final bool narrow;

  const _PillButton({
    this.prefix,
    required this.label,
    required this.onTap,
    required this.tooltip,
    required this.semanticLabel,
    this.narrow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Semantics(
          button: true,
          label: semanticLabel,
          child: Container(
            height: 38,
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 5 : 7,
              vertical: 0,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                if (prefix != null && prefix!.isNotEmpty) ...[
                  Flexible(
                    flex: 1,
                    child: Text(
                      prefix!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: narrow ? 10.0 : 11.0,
                        fontWeight: FontWeight.w500,
                        color: OrbitColors.orbitTextMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
                Flexible(
                  flex: 2,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: narrow ? 10.5 : 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: narrow ? 13 : 15,
                  color: OrbitColors.orbitTextMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact execution-mode bottom sheet:
/// PLAN: Read-only · Safe, no file changes
/// BUILD: Execute · Allows file changes
class AiModePickerSheet extends StatelessWidget {
  final bool isPlan;
  final ValueChanged<bool> onSelected;

  const AiModePickerSheet({
    super.key,
    required this.isPlan,
    required this.onSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required bool isPlan,
    required ValueChanged<bool> onSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: OrbitColors.orbitSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: OrbitColors.orbitBorder, width: 0.8),
      ),
      builder: (ctx) => AiModePickerSheet(
        isPlan: isPlan,
        onSelected: onSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: OrbitColors.orbitBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'SELECT EXECUTION MODE',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: OrbitColors.orbitTextMuted,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close mode picker',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // PLAN
            _buildOption(
              context,
              title: 'PLAN',
              subtitle: 'Read-only · Safe, no file changes',
              selected: isPlan,
              onTap: () {
                Navigator.of(context).pop();
                onSelected(true);
              },
            ),
            const SizedBox(height: 8),
            // BUILD
            _buildOption(
              context,
              title: 'BUILD',
              subtitle: 'Execute · Allows file changes',
              selected: !isPlan,
              onTap: () {
                Navigator.of(context).pop();
                onSelected(false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF1A1A1A) : OrbitColors.orbitCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? OrbitColors.orbitSilver.withValues(alpha: 0.55)
              : OrbitColors.orbitBorder,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          dense: true,
          title: Text(
            title,
            style: TextStyle(
              color: selected ? Colors.white : OrbitColors.orbitTextSecondary,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              fontFamily: 'monospace',
              fontSize: 12.5,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: OrbitColors.orbitTextMuted,
            ),
          ),
          trailing: selected
              ? const Icon(Icons.check_circle, size: 17, color: Color(0xFF10B981))
              : null,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  final bool isWorking;
  const _StatusDot({required this.isWorking});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isWorking
        ? const Color(0xFFF59E0B)
        : const Color(0xFF10B981);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(
                alpha: widget.isWorking ? 0.35 + _ctrl.value * 0.3 : 0.6,
              ),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

/// Visually quiet back affordance — present but never competing.
class _QuietIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool narrow;
  const _QuietIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.narrow = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: narrow ? 17 : 19),
      color: OrbitColors.orbitTextMuted,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: narrow ? 34 : 42,
        minHeight: narrow ? 34 : 42,
      ),
      style: IconButton.styleFrom(
        foregroundColor: OrbitColors.orbitTextMuted,
        hoverColor: Colors.white10,
        highlightColor: Colors.white10,
      ),
      onPressed: onPressed,
    );
  }
}

/// The one prominent header action: a quiet filled circle, no card row.
class _NewChatButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool narrow;
  const _NewChatButton({required this.onPressed, this.narrow = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'New conversation',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Semantics(
          button: true,
          label: 'New conversation',
          child: Container(
            width: narrow ? 34 : 42,
            height: narrow ? 34 : 42,
            alignment: Alignment.center,
            child: Container(
              width: narrow ? 24 : 28,
              height: narrow ? 24 : 28,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE4E4E7),
              ),
              child: Icon(Icons.add, size: narrow ? 15 : 16, color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderOverflowMenu extends StatelessWidget {
  final bool hasMessages;
  final int activeTaskCount;
  final VoidCallback? onClearConversation;
  final VoidCallback onOpenTasks;
  final bool narrow;
  const _HeaderOverflowMenu({
    required this.hasMessages,
    required this.activeTaskCount,
    required this.onClearConversation,
    required this.onOpenTasks,
    this.narrow = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_horiz,
        size: narrow ? 17 : 19,
        color: OrbitColors.orbitTextMuted,
      ),
      tooltip: 'More actions',
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: narrow ? 34 : 42,
        minHeight: narrow ? 34 : 42,
      ),
      color: OrbitColors.orbitSurfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: OrbitColors.orbitBorder),
      ),
      onSelected: (value) {
        if (value == 'tasks') onOpenTasks();
        if (value == 'clear') onClearConversation?.call();
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'tasks',
          child: Row(
            children: [
              const Icon(
                Icons.layers_outlined,
                size: 15,
                color: Colors.white70,
              ),
              const SizedBox(width: 10),
              Text(
                activeTaskCount > 0
                    ? 'Active tasks ($activeTaskCount)'
                    : 'Active tasks',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
        if (hasMessages && onClearConversation != null)
          const PopupMenuItem(
            value: 'clear',
            child: Row(
              children: [
                Icon(
                  Icons.delete_sweep_outlined,
                  size: 15,
                  color: Colors.white70,
                ),
                SizedBox(width: 10),
                Text(
                  'Clear conversation',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Quiet model selector: easy to tap, visually calm.
///
/// Single subtle container — no card, no shadow, no badge icon.
/// Model id is primary; provider/hint is tiny muted tertiary text.
/// Null selection renders "Default / workspace default" —
/// never "unknown", never a hardcoded model id.
class AiModelSelector extends StatelessWidget {
  final String? selectedModelId;
  final OrbitModelSummary? selectedModel;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onTap;

  const AiModelSelector({
    super.key,
    required this.selectedModelId,
    required this.selectedModel,
    this.isLoading = false,
    this.errorMessage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorMessage != null && errorMessage!.isNotEmpty;
    final isDefault = selectedModelId == null || selectedModelId!.isEmpty;

    String providerLabel;
    String modelLabel;
    String hintLabel;
    if (isLoading) {
      providerLabel = 'MODEL';
      modelLabel = 'Loading models...';
      hintLabel = 'fetching catalog';
    } else if (hasError && isDefault) {
      providerLabel = 'MODEL';
      modelLabel = 'Default';
      hintLabel = 'workspace default';
    } else if (isDefault) {
      providerLabel = 'MODEL';
      modelLabel = 'Default';
      hintLabel = 'workspace default';
    } else {
      providerLabel = _providerLabel(selectedModel?.provider);
      modelLabel = selectedModel?.id ?? selectedModelId!;
      hintLabel = selectedModel != null
          ? _capabilityHint(selectedModel!)
          : 'Workspace override';
    }

    return Tooltip(
      message: isDefault
          ? 'Select AI model (workspace default)'
          : 'Select AI model ($modelLabel)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Semantics(
          button: true,
          label: 'Select AI model, currently $modelLabel',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.025),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            providerLabel,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 8.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                              color: OrbitColors.orbitTextMuted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              modelLabel,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Padding(
                        padding: const EdgeInsets.only(left: 0),
                        child: Text(
                          hintLabel,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9.5,
                            color: OrbitColors.orbitTextMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 19,
                  color: OrbitColors.orbitTextMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _providerLabel(String? provider) {
    if (provider == null || provider.isEmpty) return 'MODEL';
    return provider.toUpperCase();
  }

  String _capabilityHint(OrbitModelSummary model) {
    final parts = <String>[];
    if (model.contextWindow != null && model.contextWindow! > 0) {
      final k = (model.contextWindow! / 1000).round();
      parts.add('${k}K context');
    }
    if (model.supportsTools) {
      parts.add('Tools');
    }
    if (parts.isEmpty) {
      return model.provider.isEmpty ? 'Selected' : model.provider;
    }
    return parts.join(' · ');
  }
}

/// Borderless secondary context row: icon + quiet text + chevron.
/// No box, no border — spacing and typography create the hierarchy.
class AiContextSelector extends StatelessWidget {
  final bool isNone;
  final String displayName;
  final String kindLabel;
  final VoidCallback onTap;

  const AiContextSelector({
    super.key,
    required this.isNone,
    required this.displayName,
    required this.kindLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Semantics(
        button: true,
        label: 'Select working context, currently $displayName',
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isNone ? Icons.public : Icons.folder_outlined,
                size: 14,
                color: OrbitColors.orbitTextMuted,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kindLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8,
                        color: OrbitColors.orbitTextMuted,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: OrbitColors.orbitTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: OrbitColors.orbitTextMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The single interactive execution-mode control (lives by the composer).
/// Typography + a tiny dot carry the selected state — no filled pills.
class AiExecutionModeSelector extends StatelessWidget {
  final bool isPlan;
  final ValueChanged<bool> onChanged;

  const AiExecutionModeSelector({
    super.key,
    required this.isPlan,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'AI execution mode, currently ${isPlan ? 'Plan read-only' : 'Build execute'}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeOption(
            selected: isPlan,
            title: 'PLAN',
            subtitle: 'read-only',
            onTap: () => onChanged(true),
          ),
          const SizedBox(width: 4),
          const Text(
            '·',
            style: TextStyle(color: OrbitColors.orbitTextMuted, fontSize: 11),
          ),
          const SizedBox(width: 4),
          _modeOption(
            selected: !isPlan,
            title: 'BUILD',
            subtitle: 'execute',
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }

  Widget _modeOption({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? Colors.white : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? Colors.white
                          : OrbitColors.orbitTextMuted.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    letterSpacing: 0.6,
                    color: selected ? Colors.white : OrbitColors.orbitTextMuted,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 11),
              child: Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 8.5,
                  letterSpacing: 0.6,
                  color: OrbitColors.orbitTextMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiny non-interactive execution-mode status for the upper context row.
/// Informational only — the composer owns the single interactive control.
class AiExecutionModeStatus extends StatelessWidget {
  final bool isPlan;
  const AiExecutionModeStatus({super.key, required this.isPlan});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Execution mode: ${isPlan ? 'Plan read-only' : 'Build execute'}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isPlan
                      ? OrbitColors.orbitTextMuted
                      : const Color(0xFFFCD34D).withValues(alpha: 0.8),
                ),
                color: isPlan ? Colors.transparent : const Color(0xFFFCD34D),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isPlan ? 'PLAN · READ-ONLY' : 'BUILD · EXECUTE',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.7,
                color: isPlan
                    ? OrbitColors.orbitTextMuted
                    : const Color(0xFFFCD34D).withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet model picker driven entirely by the loaded catalog.
class AiModelPickerSheet extends StatefulWidget {
  final List<OrbitModelSummary> models;
  final List<OrbitProviderSummary> providers;
  final String? selectedModelId;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final ValueChanged<String?> onSelected;

  const AiModelPickerSheet({
    super.key,
    required this.models,
    required this.providers,
    required this.selectedModelId,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    required this.onSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required List<OrbitModelSummary> models,
    required List<OrbitProviderSummary> providers,
    required String? selectedModelId,
    bool isLoading = false,
    String? errorMessage,
    VoidCallback? onRetry,
    required ValueChanged<String?> onSelected,
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
      builder: (ctx) => AiModelPickerSheet(
        models: models,
        providers: providers,
        selectedModelId: selectedModelId,
        isLoading: isLoading,
        errorMessage: errorMessage,
        onRetry: onRetry,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<AiModelPickerSheet> createState() => _AiModelPickerSheetState();
}

class _AiModelPickerSheetState extends State<AiModelPickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _providerFilter = 'All';
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providerNames = _availableProviderNames();
    final filtered = _filteredModels();
    final currentLabel =
        widget.selectedModelId == null || widget.selectedModelId!.isEmpty
        ? 'Default (workspace default)'
        : widget.selectedModelId!;

    return PopScope(
      canPop: true,
      child: DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollCtrl) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                child: Row(
                  children: [
                    const Text(
                      'SELECT MODEL',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: OrbitColors.textMuted,
                      ),
                      tooltip: 'Close model picker',
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E0E0E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: OrbitColors.orbitBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.hub_outlined,
                        size: 14,
                        color: OrbitColors.orbitSilver,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Current:',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: OrbitColors.orbitTextMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          currentLabel,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showSearch())
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: OrbitColors.orbitCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: OrbitColors.orbitBorder),
                    ),
                    child: TextField(
                      controller: _search,
                      autofocus: false,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        icon: const Icon(
                          Icons.search,
                          size: 16,
                          color: OrbitColors.orbitTextMuted,
                        ),
                        hintText: 'Search models...',
                        hintStyle: const TextStyle(
                          color: OrbitColors.orbitTextMuted,
                          fontSize: 12,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  size: 15,
                                  color: Colors.white70,
                                ),
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                      ),
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
                ),
              if (providerNames.length > 2)
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: providerNames.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 6),
                    itemBuilder: (ctx, i) {
                      final name = providerNames[i];
                      final selected = _providerFilter == name;
                      return ChoiceChip(
                        label: Text(
                          name,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: selected
                                ? Colors.white
                                : OrbitColors.orbitTextMuted,
                          ),
                        ),
                        selected: selected,
                        selectedColor: const Color(0xFF1E1E1E),
                        backgroundColor: Colors.transparent,
                        side: BorderSide(
                          color: selected
                              ? OrbitColors.orbitBorderLight
                              : OrbitColors.orbitBorder,
                        ),
                        onSelected: (_) =>
                            setState(() => _providerFilter = name),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 4),
              const Divider(color: OrbitColors.orbitBorder, height: 1),
              Expanded(child: _buildList(scrollCtrl, filtered)),
            ],
          );
        },
      ),
    );
  }

  bool _showSearch() {
    if (widget.isLoading) return false;
    if (widget.errorMessage != null) return false;
    return widget.models.length > 4;
  }

  List<String> _availableProviderNames() {
    final ids = <String>{};
    for (final m in widget.models) {
      if (m.provider.isNotEmpty) ids.add(m.provider);
    }
    final names = ids.toList()..sort();
    return ['All', ...names];
  }

  List<OrbitModelSummary> _filteredModels() {
    Iterable<OrbitModelSummary> out = widget.models;
    if (_providerFilter != 'All') {
      out = out.where((m) => m.provider == _providerFilter);
    }
    if (_query.isNotEmpty) {
      out = out.where(
        (m) =>
            m.id.toLowerCase().contains(_query) ||
            m.name.toLowerCase().contains(_query) ||
            m.provider.toLowerCase().contains(_query),
      );
    }
    return out.toList();
  }

  String _providerDisplayName(String providerId) {
    for (final p in widget.providers) {
      if (p.providerId == providerId) return p.name;
    }
    return providerId;
  }

  Widget _buildList(
    ScrollController scrollCtrl,
    List<OrbitModelSummary> filtered,
  ) {
    if (widget.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 12),
              Text(
                'Loading models...',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: OrbitColors.orbitTextMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (widget.errorMessage != null && widget.models.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                color: OrbitColors.orbitTextMuted,
                size: 26,
              ),
              const SizedBox(height: 10),
              const Text(
                'Unable to load models',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: OrbitColors.orbitTextMuted,
                  fontSize: 11,
                ),
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh, size: 15),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        _defaultRow(),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No models available',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'No models match this workspace or filter.',
                    style: TextStyle(
                      color: OrbitColors.orbitTextMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...filtered.map(_modelRow),
      ],
    );
  }

  Widget _defaultRow() {
    final isSelected =
        widget.selectedModelId == null || widget.selectedModelId!.isEmpty;
    return _rowShell(
      selected: isSelected,
      onTap: () {
        widget.onSelected(null);
        Navigator.of(context).pop();
      },
      title: 'Default',
      subtitle: 'Workspace default · resolved by backend',
      trailing: isSelected
          ? const Icon(Icons.check_circle, size: 17, color: Color(0xFF10B981))
          : const Icon(
              Icons.hub_outlined,
              size: 15,
              color: OrbitColors.orbitTextMuted,
            ),
    );
  }

  Widget _modelRow(OrbitModelSummary m) {
    final isSelected = m.id == widget.selectedModelId;
    final meta = <String>[_providerDisplayName(m.provider)];
    if (m.contextWindow != null && m.contextWindow! > 0) {
      meta.add('${(m.contextWindow! / 1000).round()}K context');
    }
    if (m.supportsTools) meta.add('Tools');
    return _rowShell(
      selected: isSelected,
      onTap: () {
        widget.onSelected(m.id);
        Navigator.of(context).pop();
      },
      title: m.id.isNotEmpty ? m.id : m.name,
      subtitle: meta.join(' · '),
      trailing: isSelected
          ? const Icon(Icons.check_circle, size: 17, color: Color(0xFF10B981))
          : null,
    );
  }

  Widget _rowShell({
    required bool selected,
    required VoidCallback onTap,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF1A1A1A) : OrbitColors.orbitCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? OrbitColors.orbitSilver.withValues(alpha: 0.55)
              : OrbitColors.orbitBorder,
        ),
      ),
      child: ListTile(
        dense: true,
        minVerticalPadding: 10,
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Colors.white : OrbitColors.orbitTextSecondary,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            fontFamily: 'monospace',
            fontSize: 12.5,
          ),
        ),
        subtitle: Text(
          subtitle,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: OrbitColors.orbitTextMuted,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
