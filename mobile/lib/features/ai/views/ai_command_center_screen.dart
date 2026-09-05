import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../protocol/models/ai_context.dart';
import '../../../protocol/models/ai_models.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_button.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';
import '../../../shared/widgets/orbit_logo_widget.dart';
import '../../projects/controllers/projects_controller.dart';
import '../controllers/ai_task_controller.dart';
import '../controllers/ai_permission_controller.dart';
import '../models/ai_permission_models.dart';
import '../models/ai_message.dart';
import '../widgets/ai_response_markdown.dart';
import '../widgets/permission_approval_card.dart';
import '../models/ai_conversation_models.dart';
import '../widgets/orbit_ai_header.dart';
import '../widgets/ai_conversations_history_sheet.dart';
import 'directory_picker_sheet.dart';
import 'ai_task_screen.dart';
import '../controllers/ai_conversation_controller.dart';

class AiCommandCenterScreen extends ConsumerStatefulWidget {
  final AiContext? initialContext;
  final String? initialPrompt;
  final VoidCallback? onBack;

  const AiCommandCenterScreen({
    super.key,
    this.initialContext,
    this.initialPrompt,
    this.onBack,
  });

  @override
  ConsumerState<AiCommandCenterScreen> createState() =>
      _AiCommandCenterScreenState();
}

class _AiCommandCenterScreenState extends ConsumerState<AiCommandCenterScreen> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  AiAgent _selectedAgent = AiAgent.plan;
  bool _confirmedBuildRisk = false;
  late AiContext _currentContext;

  @override
  void initState() {
    super.initState();
    _currentContext =
        widget.initialContext ??
        ref.read(aiTaskControllerProvider).currentContext;

    if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
      _promptController.text = widget.initialPrompt!;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiTaskControllerProvider.notifier).loadActiveTasks();
      ref.read(projectsControllerProvider.notifier).loadProjects();
      ref.read(aiConversationControllerProvider.notifier).loadConversations();
      ref.read(aiConversationControllerProvider.notifier).loadModels();
      ref.read(aiConversationControllerProvider.notifier).loadProviders();
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _selectContext(AiContext newContext) {
    setState(() {
      _currentContext = newContext;
    });
    ref.read(aiTaskControllerProvider.notifier).setContext(newContext);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showContextPicker(BuildContext context) {
    final projectsState = ref.read(projectsControllerProvider);
    final projects = projectsState.projects;

    showModalBottomSheet(
      context: context,
      backgroundColor: OrbitColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
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
                    color: OrbitColors.borderSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.tune,
                      color: OrbitColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'SELECT WORKING CONTEXT',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.1,
                        color: OrbitColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: OrbitColors.textMuted,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(color: OrbitColors.borderSubtle),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    // Option 1: No Context
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: _currentContext.isNone
                            ? OrbitColors.primary.withOpacity(0.12)
                            : OrbitColors.orbitCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _currentContext.isNone
                              ? OrbitColors.primary
                              : OrbitColors.borderSubtle,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: ListTile(
                          leading: Icon(
                            Icons.public,
                            color: _currentContext.isNone
                                ? OrbitColors.primary
                                : OrbitColors.textMuted,
                            size: 20,
                          ),
                          title: const Text(
                            'No Context (General Questions)',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: OrbitColors.textPrimary,
                            ),
                          ),
                          subtitle: const Text(
                            'Ask general programming questions without workstation filesystem context',
                            style: TextStyle(
                              fontSize: 11,
                              color: OrbitColors.textMuted,
                            ),
                          ),
                          trailing: _currentContext.isNone
                              ? const Icon(
                                  Icons.check,
                                  color: OrbitColors.primary,
                                  size: 18,
                                )
                              : null,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _selectContext(AiContext.none());
                          },
                        ),
                      ),
                    ),

                    // Option 2: Visual Working Directory Picker
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color:
                            _currentContext.source == AiContextSource.directory
                            ? OrbitColors.primary.withOpacity(0.12)
                            : OrbitColors.orbitCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              _currentContext.source ==
                                  AiContextSource.directory
                              ? OrbitColors.primary
                              : OrbitColors.borderSubtle,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: ListTile(
                          leading: Icon(
                            Icons.folder_open,
                            color:
                                _currentContext.source ==
                                    AiContextSource.directory
                                ? OrbitColors.primary
                                : OrbitColors.accentCyan,
                            size: 20,
                          ),
                          title: const Text(
                            'Browse Working Directory...',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: OrbitColors.textPrimary,
                            ),
                          ),
                          subtitle: const Text(
                            'Navigate and select any folder visually on your workstation',
                            style: TextStyle(
                              fontSize: 11,
                              color: OrbitColors.textMuted,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: OrbitColors.textMuted,
                            size: 18,
                          ),
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            final pickedPath = await DirectoryPickerSheet.show(
                              context,
                              initialPath: _currentContext.path,
                            );
                            if (pickedPath != null && mounted) {
                              _selectContext(
                                AiContext.fromDirectory(pickedPath),
                              );
                            }
                          },
                        ),
                      ),
                    ),

                    // Option 3: Discovered Projects
                    if (projects.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 4,
                        ),
                        child: Text(
                          'DISCOVERED PROJECTS',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: OrbitColors.textMuted,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      ...projects.map((p) {
                        final isSelected =
                            _currentContext.source == AiContextSource.project &&
                            _currentContext.path == p.path;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? OrbitColors.primary.withOpacity(0.12)
                                : OrbitColors.orbitCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? OrbitColors.primary
                                  : OrbitColors.borderSubtle,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: ListTile(
                              leading: Icon(
                                Icons.terminal,
                                color: isSelected
                                    ? OrbitColors.primary
                                    : OrbitColors.textMuted,
                                size: 20,
                              ),
                              title: Text(
                                p.name,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: OrbitColors.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                p.path,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: OrbitColors.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: isSelected
                                  ? const Icon(
                                      Icons.check,
                                      color: OrbitColors.primary,
                                      size: 18,
                                    )
                                  : null,
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _selectContext(
                                  AiContext.fromProject(
                                    path: p.path,
                                    name: p.name,
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _showBuildRiskDialog() async {
    final allowBuild = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OrbitColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: OrbitColors.borderSubtle),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: OrbitColors.warning,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'CONFIRM BUILD MODE',
              style: TextStyle(
                color: OrbitColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        content: const Text(
          'Build mode allows Orbit AI to create and modify files on your workstation.\n\nAre you sure you want to proceed with executing in Build mode?',
          style: TextStyle(
            color: OrbitColors.textMuted,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: OrbitColors.textMuted),
            ),
          ),
          OrbitButton(
            text: 'Allow Build',
            variant: OrbitButtonVariant.primary,
            onPressed: () {
              setState(() => _confirmedBuildRisk = true);
              Navigator.of(ctx).pop(true);
            },
          ),
        ],
      ),
    );
    return allowBuild == true;
  }

  void _showModePickerSheet() {
    AiModePickerSheet.show(
      context,
      isPlan: _selectedAgent == AiAgent.plan,
      onSelected: (isPlan) async {
        if (!isPlan && !_confirmedBuildRisk) {
          final allow = await _showBuildRiskDialog();
          if (!allow) return;
        }
        setState(() {
          _selectedAgent = isPlan ? AiAgent.plan : AiAgent.build;
        });
      },
    );
  }

  String _modelLabel(AiConversationState convState) {
    if (convState.selectedModel == null || convState.selectedModel!.isEmpty) {
      return 'Default';
    }
    final model = _resolveSelectedModel(convState);
    return model?.id ?? convState.selectedModel!;
  }

  String _contextLabel() {
    if (_currentContext.isNone) {
      return 'No context';
    }
    if (_currentContext.source == AiContextSource.project) {
      return 'Project: ${_currentContext.displayName}';
    }
    return 'Directory: ${_currentContext.displayName}';
  }

  Future<void> _submitCommand() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    if (_selectedAgent == AiAgent.build && !_confirmedBuildRisk) {
      final allowBuild = await _showBuildRiskDialog();
      if (!allowBuild) return;
    }

    _promptController.clear();
    final controller = ref.read(aiTaskControllerProvider.notifier);
    final isReadOnly = _selectedAgent == AiAgent.plan;

    final convState = ref.read(aiConversationControllerProvider);
    await controller.sendMessage(
      prompt,
      context: _currentContext,
      agent: _selectedAgent,
      readOnly: isReadOnly,
      conversationId: convState.activeConversation?.summary.id,
      model: convState.selectedModel,
    );
    ref.read(aiConversationControllerProvider.notifier).loadConversations();

    _scrollToBottom();
  }

  void _confirmClearConversation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OrbitColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: OrbitColors.borderSubtle),
        ),
        title: const Text(
          'CLEAR CONVERSATION',
          style: TextStyle(
            color: OrbitColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        content: const Text(
          'Are you sure you want to clear the conversation history? This will not affect files on your workstation.',
          style: TextStyle(color: OrbitColors.textMuted, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: OrbitColors.textMuted),
            ),
          ),
          OrbitButton(
            text: 'Clear',
            variant: OrbitButtonVariant.danger,
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(aiTaskControllerProvider.notifier).clearConversation();
              ref
                  .read(aiConversationControllerProvider.notifier)
                  .clearActiveConversation();
            },
          ),
        ],
      ),
    );
  }

  void _showConversationsHistorySheet() {
    AiConversationsHistorySheet.show(
      context,
      onContextSelected: _selectContext,
    );
  }

  OrbitModelSummary? _resolveSelectedModel(AiConversationState convState) {
    final id = convState.selectedModel;
    if (id == null || id.isEmpty) return null;
    for (final m in convState.availableModels) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _showModelPickerSheet() {
    final convState = ref.read(aiConversationControllerProvider);
    AiModelPickerSheet.show(
      context,
      models: convState.availableModels,
      providers: convState.availableProviders,
      selectedModelId: convState.selectedModel,
      isLoading:
          convState.availableModels.isEmpty && convState.errorMessage == null,
      errorMessage: convState.availableModels.isEmpty
          ? convState.errorMessage
          : null,
      onRetry: () =>
          ref.read(aiConversationControllerProvider.notifier).loadModels(),
      onSelected: (id) => ref
          .read(aiConversationControllerProvider.notifier)
          .setSelectedModel(id),
    );
  }

  void _openActiveTasks() {
    final state = ref.read(aiTaskControllerProvider);
    if (state.activeTask != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AiTaskScreen(
            projectPath: _currentContext.path ?? '',
            projectName: _currentContext.displayName,
            initialTask: state.activeTask,
          ),
        ),
      );
    } else {
      ref.read(aiTaskControllerProvider.notifier).loadActiveTasks();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active task. Start a command below!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiTaskControllerProvider);
    final isWorking = state.isWorking;
    final messages = state.messages;
    final canPopRoute = Navigator.of(context).canPop();
    final showLeading = widget.onBack != null || canPopRoute;

    return PopScope(
      canPop: !canPopRoute && widget.onBack == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (canPopRoute) {
          Navigator.of(context).pop();
        } else if (widget.onBack != null) {
          widget.onBack!();
        }
      },
      child: Scaffold(
        backgroundColor: OrbitColors.orbitBackground,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: OrbitAiHeader(
            showLeading: showLeading,
            onBack: widget.onBack,
            isWorking: isWorking,
            activeTaskCount: state.activeTasks.length,
            onOpenHistory: _showConversationsHistorySheet,
            onNewChat: () {
              ref
                  .read(aiConversationControllerProvider.notifier)
                  .clearActiveConversation();
              ref
                  .read(aiTaskControllerProvider.notifier)
                  .clearConversation();
            },
            onClearConversation: messages.isNotEmpty
                ? _confirmClearConversation
                : null,
            onOpenTasks: _openActiveTasks,
            hasMessages: messages.isNotEmpty,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Single compact AI control row: [ Default ▾ ] [ No context ▾ ] [ Plan ▾ ]
              Consumer(
                builder: (context, ref, _) {
                  final convState = ref.watch(aiConversationControllerProvider);
                  return AiControlBar(
                    modelLabel: _modelLabel(convState),
                    onOpenModelPicker: _showModelPickerSheet,
                    contextLabel: _contextLabel(),
                    onOpenContextPicker: () => _showContextPicker(context),
                    isPlan: _selectedAgent == AiAgent.plan,
                    onOpenModePicker: _showModePickerSheet,
                  );
                },
              ),

              // Unattached pending permission requests
              Builder(
                builder: (context) {
                  final permState = ref.watch(aiPermissionControllerProvider);
                  final unattachedPerms = permState.pendingRequests
                      .where((p) => !messages.any((m) => m.taskId == p.taskId))
                      .toList();

                  if (unattachedPerms.isEmpty) return const SizedBox.shrink();

                  return Container(
                    width: double.infinity,
                    color: const Color(0xFF161308),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.shield_outlined,
                                size: 14,
                                color: Color(0xFFFCD34D),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'AI PERMISSION REQUIRED (${unattachedPerms.length})',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFCD34D),
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final req in unattachedPerms)
                          PermissionApprovalCard(request: req),
                      ],
                    ),
                  );
                },
              ),

              // Conversation Messages Area (Chat First - dominates the viewport)
              Expanded(
                child: messages.isEmpty
                    ? _buildEmptyState()
                    : _buildConversationList(messages, state),
              ),

              // Composer Area
              _buildComposer(isWorking, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        const SizedBox(height: 12),
        // Glowing Orbital Eclipse Graphic
        const Center(child: OrbitEclipseGraphic(size: 110)),
        const SizedBox(height: 20),
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ORBIT AI',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(
                height: 0,
                width: 0,
                child: Opacity(
                  opacity: 0,
                  child: Text(
                    'ORBIT AI COMMAND CENTER',
                    style: TextStyle(fontSize: 0.001),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'Your development environment,\nunderstood.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: OrbitColors.orbitAccentCyan,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'Ask questions, explore architecture, or execute tasks directly on your machine.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: OrbitColors.orbitTextMuted,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'SUGGESTED COMMANDS',
          style: TextStyle(
            color: OrbitColors.orbitTextMuted,
            fontFamily: 'monospace',
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        _buildSuggestionChip('Explain README.md', Icons.description_outlined),
        _buildSuggestionChip(
          'What does this project do?',
          Icons.help_outline_rounded,
        ),
        _buildSuggestionChip(
          'Inspect project architecture',
          Icons.account_tree_outlined,
        ),
        _buildSuggestionChip(
          'Run flutter analyze and explain results',
          Icons.science_outlined,
        ),
      ],
    );
  }

  Widget _buildSuggestionChip(String prompt, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: OrbitColors.orbitCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OrbitColors.orbitBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 2,
          ),
          leading: Icon(icon, color: Colors.white, size: 18),
          title: Text(
            prompt,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontFamily: 'monospace',
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: OrbitColors.orbitTextMuted,
          ),
          onTap: () {
            _promptController.text = prompt;
            _submitCommand();
          },
        ),
      ),
    );
  }

  Widget _buildConversationList(List<AiMessage> messages, AiTaskState state) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        if (msg.isUser) {
          return _buildUserMessageItem(msg);
        } else {
          return _buildAssistantMessageItem(msg, state);
        }
      },
    );
  }

  Widget _buildUserMessageItem(AiMessage msg) {
    final timeStr = DateFormat('HH:mm').format(msg.timestamp);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16, left: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (msg.contextPath != null &&
                      msg.contextPath!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: OrbitColors.orbitCard,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: OrbitColors.orbitBorder),
                      ),
                      child: Text(
                        msg.contextPath!.split('/').last,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          color: OrbitColors.orbitTextMuted,
                        ),
                      ),
                    ),
                  ],
                  const Text(
                    'You',
                    style: TextStyle(
                      color: Color(0xFFD8D8D8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: OrbitColors.orbitTextMuted,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: OrbitColors.orbitBorder),
              ),
              child: SelectableText(
                msg.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantMessageItem(AiMessage msg, AiTaskState state) {
    final isWorking = msg.isWorking;
    final timeStr = DateFormat('HH:mm').format(msg.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 20, right: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C0C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWorking
              ? OrbitColors.orbitBorderLight
              : OrbitColors.orbitBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
              border: const Border(
                bottom: BorderSide(color: OrbitColors.orbitBorder),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isWorking ? Colors.white : Colors.white70,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'ORBIT AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isWorking
                          ? Colors.white.withValues(alpha: 0.3)
                          : (msg.status == AiMessageStatus.failed
                                ? OrbitColors.orbitError.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.2)),
                    ),
                  ),
                  child: Text(
                    isWorking
                        ? 'WORKING'
                        : (msg.status == AiMessageStatus.failed
                              ? 'FAILED'
                              : 'COMPLETED'),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: isWorking
                          ? Colors.white
                          : (msg.status == AiMessageStatus.failed
                                ? OrbitColors.orbitError
                                : const Color(0xFFD8D8D8)),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  timeStr,
                  style: const TextStyle(
                    color: OrbitColors.orbitTextMuted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
                if (msg.text.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: msg.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('AI Response copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 13,
                        color: OrbitColors.orbitTextMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Pending permission requests for this specific task
                Consumer(
                  builder: (context, ref, _) {
                    final permState = ref.watch(aiPermissionControllerProvider);
                    final taskPerms = msg.taskId != null
                        ? permState.pendingRequests
                              .where((p) => p.taskId == msg.taskId)
                              .toList()
                        : <AiPermissionRequest>[];
                    if (taskPerms.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final req in taskPerms)
                          PermissionApprovalCard(request: req),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),

                // 1. Current Activity (if actively working)
                if (isWorking && msg.currentActivity != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: OrbitColors.orbitBorderLight),
                    ),
                    child: Row(
                      children: [
                        OrbitLoadingIndicator(
                          size: 16,
                          minOpacity: 0.15,
                          maxOpacity: 0.95,
                          duration: Duration(milliseconds: 950),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CURRENT ACTIVITY',
                                style: TextStyle(
                                  color: OrbitColors.orbitTextMuted,
                                  fontSize: 8.5,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                msg.currentActivity!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: OrbitColors.orbitTextMuted,
                        ),
                      ],
                    ),
                  ),
                ],

                // 2. Technical Timeline (collapsible stepper)
                if (msg.activities.isNotEmpty) ...[
                  _buildCollapsibleTimeline(msg.activities, isWorking),
                  const SizedBox(height: 12),
                ],

                // 3. Assistant Response
                if (msg.text.isNotEmpty) ...[
                  AiResponseMarkdown(text: msg.text),
                ] else if (isWorking) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        OrbitLoadingIndicator(
                          size: 16,
                          minOpacity: 0.15,
                          maxOpacity: 0.95,
                          duration: Duration(milliseconds: 950),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Orbit AI is formulating response...',
                          style: TextStyle(
                            color: OrbitColors.orbitTextMuted,
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 4. Error Card
                if (msg.error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: OrbitColors.orbitError.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: OrbitColors.orbitError.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 16,
                          color: OrbitColors.orbitError,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            msg.error!,
                            style: const TextStyle(
                              color: OrbitColors.orbitError,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 5. Stop task button if working
                if (isWorking && msg.taskId != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () {
                        ref
                            .read(aiTaskControllerProvider.notifier)
                            .cancelTask(msg.taskId!);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161616),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: OrbitColors.orbitBorder),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.stop_circle_outlined,
                              size: 14,
                              color: Colors.white,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Stop Task',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsibleTimeline(
    List<AiActivity> activities,
    bool isWorking,
  ) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        collapsedIconColor: OrbitColors.orbitTextMuted,
        iconColor: Colors.white,
        title: Row(
          children: [
            Icon(
              isWorking
                  ? Icons.autorenew_rounded
                  : Icons.check_circle_outline_rounded,
              size: 15,
              color: isWorking ? Colors.white : const Color(0xFF10B981),
            ),
            const SizedBox(width: 6),
            Text(
              'Technical Timeline (${activities.length} ${activities.length == 1 ? "action" : "actions"})',
              style: const TextStyle(
                color: OrbitColors.orbitTextSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF101010),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: OrbitColors.orbitBorder),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activities.length,
              itemBuilder: (context, idx) {
                final act = activities[idx];
                final isDone = act.status == AiActivityStatus.completed;
                final isFailed = act.status == AiActivityStatus.failed;
                final isLast = idx == activities.length - 1;

                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Vertical Stepper Column
                      Column(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDone
                                  ? Colors.white
                                  : (isFailed
                                        ? OrbitColors.orbitError
                                        : Colors.transparent),
                              border: Border.all(
                                color: isDone
                                    ? Colors.white
                                    : (isFailed
                                          ? OrbitColors.orbitError
                                          : Colors.white70),
                                width: 1.5,
                              ),
                            ),
                          ),
                          if (!isLast)
                            Expanded(
                              child: Container(
                                width: 1,
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                color: OrbitColors.orbitBorder,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      // Content
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                act.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (act.filePath != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    act.filePath!,
                                    style: const TextStyle(
                                      color: OrbitColors.orbitTextMuted,
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (act.durationMs != null)
                        Text(
                          '${(act.durationMs! / 1000).toStringAsFixed(1)}s',
                          style: const TextStyle(
                            color: OrbitColors.orbitTextMuted,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(bool isWorking, AiTaskState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: const BoxDecoration(
        color: OrbitColors.orbitSurface,
        border: Border(
          top: BorderSide(color: OrbitColors.orbitBorder, width: 0.8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0E0E0E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: OrbitColors.orbitBorder, width: 0.8),
                ),
                child: TextField(
                  controller: _promptController,
                  maxLines: 4,
                  minLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: isWorking
                        ? 'Orbit AI is working...'
                        : 'Ask Orbit... (e.g. "Explain README.md")',
                    hintStyle: const TextStyle(
                      color: OrbitColors.orbitTextMuted,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) {
                    if (!isWorking) _submitCommand();
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Action Button (Send or Cancel)
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: OrbitColors.orbitBorder, width: 0.8),
              ),
              child: isWorking
                  ? IconButton(
                      icon: const Icon(
                        Icons.stop_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                      tooltip: 'Stop running task',
                      onPressed: () {
                        if (state.activeTask != null) {
                          ref
                              .read(aiTaskControllerProvider.notifier)
                              .cancelTask(state.activeTask!.taskId);
                        }
                      },
                    )
                  : IconButton(
                      icon: const Icon(
                        Icons.arrow_upward_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                      tooltip: 'Send prompt',
                      onPressed: _submitCommand,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
