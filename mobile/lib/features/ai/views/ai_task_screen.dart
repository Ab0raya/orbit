import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../protocol/models/ai_models.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_button.dart';
import '../../../shared/widgets/orbit_card.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';
import '../controllers/ai_task_controller.dart';
import '../widgets/ai_response_markdown.dart';

class AiTaskScreen extends ConsumerStatefulWidget {
  final String projectPath;
  final String projectName;
  final AiTask? initialTask;

  const AiTaskScreen({
    super.key,
    required this.projectPath,
    required this.projectName,
    this.initialTask,
  });

  @override
  ConsumerState<AiTaskScreen> createState() => _AiTaskScreenState();
}

class _AiTaskScreenState extends ConsumerState<AiTaskScreen> {
  Timer? _timer;
  int _secondsElapsed = 0;
  final _followUpController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _userScrolledUp = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialTask != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = ref.read(aiTaskControllerProvider.notifier);
        controller.setActiveTask(widget.initialTask!);
        controller.fetchTaskDetails(widget.initialTask!.taskId);
      });
    }

    _scrollController.addListener(_onScroll);
    _startTimer();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    final isScrolledUp = (maxScroll - currentScroll) > 100;
    if (isScrolledUp != _userScrolledUp) {
      setState(() {
        _userScrolledUp = isScrolledUp;
      });
    }
  }

  void _scrollToBottom({bool force = false}) {
    if ((!_userScrolledUp || force) && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final task = ref.read(aiTaskControllerProvider).activeTask;
      if (task != null && !task.status.isTerminal) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _followUpController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _confirmCancel(String taskId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OrbitColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: OrbitColors.borderSubtle),
        ),
        title: const Text(
          'CANCEL AI TASK',
          style: TextStyle(
            color: OrbitColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        content: const Text(
          'Are you sure you want to stop this AI task? The OpenCode process on your PC will be terminated safely.',
          style: TextStyle(
            color: OrbitColors.textMuted,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Running', style: TextStyle(color: OrbitColors.textMuted)),
          ),
          OrbitButton(
            text: 'Stop Task',
            variant: OrbitButtonVariant.danger,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(aiTaskControllerProvider.notifier).cancelTask(taskId);
    }
  }

  Future<void> _sendFollowUp(String sessionId) async {
    final prompt = _followUpController.text.trim();
    if (prompt.isEmpty) return;

    _followUpController.clear();
    final controller = ref.read(aiTaskControllerProvider.notifier);
    final currentTask = ref.read(aiTaskControllerProvider).activeTask;

    await controller.resumeTask(
      sessionId,
      widget.projectPath,
      prompt,
      agent: currentTask?.agent ?? AiAgent.plan,
      readOnly: currentTask?.readOnly ?? true,
    );
  }

  void _showToolDetails(AiActivity activity) {
    showModalBottomSheet(
      context: context,
      backgroundColor: OrbitColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: OrbitColors.borderSubtle),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildActivityIcon(activity.activityType, size: 18),
                const SizedBox(width: 8),
                Text(
                  activity.tool != null
                      ? 'TOOL: ${activity.tool!.toUpperCase()}'
                      : activity.activityType.name.toUpperCase(),
                  style: const TextStyle(
                    color: OrbitColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: activity.status == AiActivityStatus.completed
                        ? Colors.greenAccent.withValues(alpha: 0.15)
                        : (activity.status == AiActivityStatus.failed
                            ? OrbitColors.error.withValues(alpha: 0.15)
                            : OrbitColors.primary.withValues(alpha: 0.15)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    activity.status.name.toUpperCase(),
                    style: TextStyle(
                      color: activity.status == AiActivityStatus.completed
                          ? Colors.greenAccent
                          : (activity.status == AiActivityStatus.failed
                              ? OrbitColors.error
                              : OrbitColors.primary),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              activity.title,
              style: const TextStyle(
                color: OrbitColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            if (activity.command != null) ...[
              const SizedBox(height: 12),
              const Text(
                'COMMAND',
                style: TextStyle(
                  color: OrbitColors.textMuted,
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: OrbitColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: OrbitColors.borderSubtle),
                ),
                child: SelectableText(
                  activity.command!,
                  style: const TextStyle(
                    color: OrbitColors.accentCyan,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            if (activity.filePath != null) ...[
              const SizedBox(height: 12),
              const Text(
                'FILE PATH',
                style: TextStyle(
                  color: OrbitColors.textMuted,
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                activity.filePath!,
                style: const TextStyle(
                  color: OrbitColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (activity.durationMs != null) ...[
                  const Text(
                    'Duration: ',
                    style: TextStyle(color: OrbitColors.textMuted, fontSize: 11, fontFamily: 'monospace'),
                  ),
                  Text(
                    '${(activity.durationMs! / 1000).toStringAsFixed(1)}s',
                    style: const TextStyle(color: OrbitColors.textPrimary, fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(width: 16),
                ],
                if (activity.exitCode != null) ...[
                  const Text(
                    'Exit Code: ',
                    style: TextStyle(color: OrbitColors.textMuted, fontSize: 11, fontFamily: 'monospace'),
                  ),
                  Text(
                    '${activity.exitCode}',
                    style: TextStyle(
                      color: activity.exitCode == 0 ? Colors.greenAccent : OrbitColors.error,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiTaskControllerProvider);
    final task = state.activeTask;

    if (!_userScrolledUp) {
      _scrollToBottom();
    }

    return Scaffold(
      backgroundColor: OrbitColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: OrbitColors.surfaceDark,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI COMMAND CENTER',
              style: TextStyle(
                color: OrbitColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 1.2,
              ),
            ),
            Text(
              widget.projectName,
              style: const TextStyle(
                color: OrbitColors.primary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _userScrolledUp
          ? FloatingActionButton.small(
              backgroundColor: OrbitColors.primary,
              foregroundColor: OrbitColors.backgroundDark,
              onPressed: () {
                setState(() {
                  _userScrolledUp = false;
                });
                _scrollToBottom(force: true);
              },
              child: const Icon(Icons.arrow_downward, size: 18),
            )
          : null,
      body: task == null
          ? const Center(
              child: Text(
                'No active task found',
                style: TextStyle(color: OrbitColors.textMuted, fontFamily: 'monospace'),
              ),
            )
          : ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeaderCard(task),
                const SizedBox(height: 14),
                _buildCurrentActivityCard(task, state.currentActivity),
                const SizedBox(height: 16),
                if (task.status == AiTaskStatus.completed) ...[
                  _buildCompletionSummaryCard(task, state.activities),
                  const SizedBox(height: 16),
                ] else if (task.status == AiTaskStatus.failed) ...[
                  _buildFailedSummaryCard(task),
                  const SizedBox(height: 16),
                ] else if (task.status == AiTaskStatus.cancelled) ...[
                  _buildCancelledSummaryCard(task),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    const Text(
                      'TECHNICAL TIMELINE',
                      style: TextStyle(
                        color: OrbitColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Spacer(),
                    if (!task.status.isTerminal)
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: OrbitColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'LIVE',
                            style: TextStyle(
                              color: OrbitColors.primary,
                              fontSize: 10,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildTimelineCard(state.activities, task),
                const SizedBox(height: 16),
                if (task.response != null && task.response!.trim().isNotEmpty) ...[
                  _buildAssistantResponseCard(task),
                  const SizedBox(height: 16),
                ],
                if (state.accumulatedOutput.isNotEmpty || task.output != null) ...[
                  _buildOutputCard(
                    state.accumulatedOutput.isNotEmpty
                        ? state.accumulatedOutput
                        : (task.output ?? ''),
                  ),
                  const SizedBox(height: 16),
                ],
                if (task.status == AiTaskStatus.completed && task.openCodeSessionId != null) ...[
                  _buildFollowUpCard(task.openCodeSessionId!),
                  const SizedBox(height: 24),
                ],
              ],
            ),
    );
  }

  Widget _buildHeaderCard(AiTask task) {
    final statusColor = _getStatusColor(task.status);

    return OrbitCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      task.status.name.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: OrbitColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: OrbitColors.borderSubtle),
                ),
                child: Text(
                  task.agent.name.toUpperCase(),
                  style: const TextStyle(
                    color: OrbitColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 14, color: OrbitColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(_secondsElapsed),
                    style: const TextStyle(
                      color: OrbitColors.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'TASK // ${task.taskId}',
            style: const TextStyle(
              color: OrbitColors.textMuted,
              fontSize: 10,
              fontFamily: 'monospace',
              letterSpacing: 0.8,
            ),
          ),
          if (task.openCodeSessionId != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'Session: ',
                  style: TextStyle(
                    color: OrbitColors.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  task.openCodeSessionId!,
                  style: const TextStyle(
                    color: OrbitColors.accentCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
          if (!task.status.isTerminal) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OrbitButton(
                text: 'Stop Task',
                variant: OrbitButtonVariant.danger,
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                onPressed: () => _confirmCancel(task.taskId),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentActivityCard(AiTask task, AiActivity? current) {
    if (task.status == AiTaskStatus.completed) {
      return OrbitCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: const [
            Icon(Icons.check_circle, size: 18, color: Colors.greenAccent),
            SizedBox(width: 10),
            Text(
              'Task completed',
              style: TextStyle(
                color: Colors.greenAccent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    if (task.status == AiTaskStatus.failed) {
      return OrbitCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: const [
            Icon(Icons.cancel, size: 18, color: OrbitColors.error),
            SizedBox(width: 10),
            Text(
              'Task failed',
              style: TextStyle(
                color: OrbitColors.error,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    if (task.status == AiTaskStatus.cancelled) {
      return OrbitCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: const [
            Icon(Icons.stop, size: 18, color: OrbitColors.textMuted),
            SizedBox(width: 10),
            Text(
              'Task cancelled',
              style: TextStyle(
                color: OrbitColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    final title = current?.title ?? 'Waiting for AI activity...';
    final isRunning = task.status == AiTaskStatus.running;

    return OrbitCard(
      padding: const EdgeInsets.all(14),
      borderColor: isRunning ? OrbitColors.primary.withValues(alpha: 0.5) : OrbitColors.borderSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'CURRENT ACTIVITY',
                style: TextStyle(
                  color: OrbitColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              if (isRunning)
                const OrbitLoadingIndicator(
                  size: 18,
                  minOpacity: 0.2,
                  maxOpacity: 0.9,
                  duration: Duration(milliseconds: 900),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (current != null) ...[
                _buildActivityIcon(current.activityType, size: 16),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: OrbitColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          if (current?.command != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: OrbitColors.surfaceHighlight,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                current!.command!,
                style: const TextStyle(
                  color: OrbitColors.accentCyan,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletionSummaryCard(AiTask task, List<AiActivity> activities) {
    final toolsCount = activities.where((a) => a.tool != null).length;
    final touchedFiles = activities
        .map((a) => a.filePath)
        .where((p) => p != null && p.isNotEmpty)
        .toSet()
        .length;

    return OrbitCard(
      padding: const EdgeInsets.all(16),
      borderColor: Colors.greenAccent.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.verified, color: Colors.greenAccent, size: 18),
              SizedBox(width: 8),
              Text(
                'TASK COMPLETED',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetricItem('Duration', _formatDuration(_secondsElapsed)),
              _buildMetricItem('Activities', '${activities.length}'),
              _buildMetricItem('Tools', '$toolsCount'),
              _buildMetricItem('Files', '$touchedFiles'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: OrbitColors.textMuted,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: OrbitColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildFailedSummaryCard(AiTask task) {
    return OrbitCard(
      padding: const EdgeInsets.all(14),
      borderColor: OrbitColors.error.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.error_outline, color: OrbitColors.error, size: 18),
              SizedBox(width: 8),
              Text(
                'TASK FAILED',
                style: TextStyle(
                  color: OrbitColors.error,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            task.error ?? 'OpenCode process exited unexpectedly.',
            style: const TextStyle(
              color: OrbitColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelledSummaryCard(AiTask task) {
    return OrbitCard(
      padding: const EdgeInsets.all(14),
      borderColor: OrbitColors.textMuted.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.stop_circle, color: OrbitColors.textMuted, size: 18),
              SizedBox(width: 8),
              Text(
                'TASK CANCELLED',
                style: TextStyle(
                  color: OrbitColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'The AI task was stopped. OpenCode child process was terminated.',
            style: TextStyle(
              color: OrbitColors.textSecondary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(List<AiActivity> activities, AiTask task) {
    if (activities.isEmpty) {
      return OrbitCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const OrbitLoadingIndicator(
              size: 20,
              minOpacity: 0.2,
              maxOpacity: 0.9,
              duration: Duration(milliseconds: 900),
            ),
            const SizedBox(width: 12),
            Text(
              task.status == AiTaskStatus.queued
                  ? 'Waiting in queue...'
                  : 'OpenCode starting up...',
              style: const TextStyle(
                color: OrbitColors.textMuted,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    return OrbitCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: activities.length,
        separatorBuilder: (_, _) => const Divider(
          height: 14,
          color: OrbitColors.borderSubtle,
        ),
        itemBuilder: (context, index) {
          final act = activities[index];
          final isLatest = index == activities.length - 1;

          return InkWell(
            onTap: () => _showToolDetails(act),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildActivityIcon(act.activityType, size: 14),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          act.title,
                          style: TextStyle(
                            color: isLatest ? OrbitColors.textPrimary : OrbitColors.textSecondary,
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: isLatest ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (act.command != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            act.command!,
                            style: const TextStyle(
                              color: OrbitColors.accentCyan,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ] else if (act.filePath != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            act.filePath!,
                            style: const TextStyle(
                              color: OrbitColors.textMuted,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (act.durationMs != null)
                    Text(
                      '${(act.durationMs! / 1000).toStringAsFixed(1)}s',
                      style: const TextStyle(
                        color: OrbitColors.textMuted,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActivityIcon(AiActivityType type, {double size = 14}) {
    switch (type) {
      case AiActivityType.command:
        return Icon(Icons.terminal, size: size, color: OrbitColors.primary);
      case AiActivityType.testing:
        return Icon(Icons.science, size: size, color: Colors.greenAccent);
      case AiActivityType.reading:
        return Icon(Icons.description, size: size, color: OrbitColors.accentCyan);
      case AiActivityType.writing:
        return Icon(Icons.edit_note, size: size, color: Colors.amberAccent);
      case AiActivityType.thinking:
        return Icon(Icons.memory, size: size, color: OrbitColors.primary);
      case AiActivityType.completed:
        return Icon(Icons.check_circle_outline, size: size, color: Colors.greenAccent);
      case AiActivityType.error:
        return Icon(Icons.error_outline, size: size, color: OrbitColors.error);
      case AiActivityType.waiting:
        return Icon(Icons.hourglass_empty, size: size, color: OrbitColors.textMuted);
      case AiActivityType.permissionRequired:
        return Icon(Icons.shield_outlined, size: size, color: const Color(0xFFF59E0B));
      case AiActivityType.tool:
        return Icon(Icons.build_outlined, size: size, color: OrbitColors.textSecondary);
    }
  }

  Widget _buildAssistantResponseCard(AiTask task) {
    final responseText = task.response;
    if (responseText == null || responseText.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return OrbitCard(
      padding: const EdgeInsets.all(14),
      borderColor: OrbitColors.primary.withOpacity(0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: OrbitColors.primary),
              const SizedBox(width: 8),
              const Text(
                'ASSISTANT RESPONSE',
                style: TextStyle(
                  color: OrbitColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 16, color: OrbitColors.textMuted),
                tooltip: 'Copy Response',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: responseText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Response copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          AiResponseMarkdown(text: responseText),
        ],
      ),
    );
  }

  Widget _buildOutputCard(String output) {
    return OrbitCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'TASK OUTPUT',
                style: TextStyle(
                  color: OrbitColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 16, color: OrbitColors.textMuted),
                tooltip: 'Copy Output',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: output));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Output copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: OrbitColors.surfaceHighlight,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: OrbitColors.borderSubtle),
            ),
            child: SelectableText(
              output,
              style: const TextStyle(
                color: OrbitColors.textPrimary,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowUpCard(String sessionId) {
    return OrbitCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CONTINUE SESSION',
            style: TextStyle(
              color: OrbitColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _followUpController,
                  style: const TextStyle(
                    color: OrbitColors.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter follow-up instruction...',
                    hintStyle: const TextStyle(
                      color: OrbitColors.textMuted,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.all(10),
                    filled: true,
                    fillColor: OrbitColors.surfaceHighlight,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: OrbitColors.borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: OrbitColors.primary),
                    ),
                  ),
                  onSubmitted: (_) => _sendFollowUp(sessionId),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, size: 18, color: OrbitColors.primary),
                onPressed: () => _sendFollowUp(sessionId),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(AiTaskStatus status) {
    switch (status) {
      case AiTaskStatus.running:
        return OrbitColors.primary;
      case AiTaskStatus.completed:
        return Colors.greenAccent;
      case AiTaskStatus.failed:
        return OrbitColors.error;
      case AiTaskStatus.cancelled:
        return OrbitColors.textMuted;
      case AiTaskStatus.queued:
        return Colors.amberAccent;
    }
  }
}
