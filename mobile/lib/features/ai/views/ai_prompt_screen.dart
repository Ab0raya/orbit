import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../protocol/models/ai_models.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_button.dart';
import '../../../shared/widgets/orbit_card.dart';
import '../controllers/ai_task_controller.dart';
import 'ai_task_screen.dart';

class AiPromptScreen extends ConsumerStatefulWidget {
  final String projectPath;
  final String projectName;

  const AiPromptScreen({
    super.key,
    required this.projectPath,
    required this.projectName,
  });

  @override
  ConsumerState<AiPromptScreen> createState() => _AiPromptScreenState();
}

class _AiPromptScreenState extends ConsumerState<AiPromptScreen> {
  final _promptController = TextEditingController();
  AiAgent _selectedAgent = AiAgent.plan;
  bool _confirmedBuildRisk = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _startTask() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a prompt describing your task.'),
          backgroundColor: OrbitColors.error,
        ),
      );
      return;
    }

    if (_selectedAgent == AiAgent.build && !_confirmedBuildRisk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please confirm you understand Build mode can modify files.'),
          backgroundColor: OrbitColors.warning,
        ),
      );
      return;
    }

    final controller = ref.read(aiTaskControllerProvider.notifier);
    final isReadOnly = _selectedAgent == AiAgent.plan;

    final task = await controller.startTask(
      widget.projectPath,
      prompt,
      agent: _selectedAgent,
      readOnly: isReadOnly,
    );

    if (!mounted) return;

    if (task != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AiTaskScreen(
            projectPath: widget.projectPath,
            projectName: widget.projectName,
            initialTask: task,
          ),
        ),
      );
    } else {
      final error = ref.read(aiTaskControllerProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Failed to start AI task'),
          backgroundColor: OrbitColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiTaskControllerProvider);

    return Scaffold(
      backgroundColor: OrbitColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: OrbitColors.surfaceDark,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI TASK COMPOSER',
              style: TextStyle(
                color: OrbitColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 1.1,
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Project Scope Card
          OrbitCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 18, color: OrbitColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.projectName,
                        style: const TextStyle(
                          color: OrbitColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        widget.projectPath,
                        style: const TextStyle(
                          color: OrbitColors.textMuted,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Agent Mode Selector
          const Text(
            'EXECUTION MODE',
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
                child: _buildModeOption(
                  agent: AiAgent.plan,
                  title: 'PLAN',
                  subtitle: 'Read-only analysis',
                  isSelected: _selectedAgent == AiAgent.plan,
                  color: OrbitColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildModeOption(
                  agent: AiAgent.build,
                  title: 'BUILD',
                  subtitle: 'Mutating execution',
                  isSelected: _selectedAgent == AiAgent.build,
                  color: Colors.amberAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Mode Description Card
          OrbitCard(
            padding: const EdgeInsets.all(12),
            backgroundColor: OrbitColors.surfaceHighlight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _selectedAgent == AiAgent.plan
                      ? Icons.shield_outlined
                      : Icons.warning_amber_rounded,
                  size: 18,
                  color: _selectedAgent == AiAgent.plan
                      ? OrbitColors.primary
                      : Colors.amberAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedAgent == AiAgent.plan
                        ? 'Read-only analysis. OpenCode will inspect code, architecture, and configuration without editing files or executing modifying commands.'
                        : 'Mutating execution. OpenCode can edit project files, create files, and execute shell development commands.',
                    style: const TextStyle(
                      color: OrbitColors.textSecondary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Build Mode Confirmation Checkbox if Build selected
          if (_selectedAgent == AiAgent.build) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
              ),
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _confirmedBuildRisk,
                activeColor: Colors.amberAccent,
                checkColor: OrbitColors.backgroundDark,
                onChanged: (val) {
                  setState(() {
                    _confirmedBuildRisk = val ?? false;
                  });
                },
                title: const Text(
                  'I confirm OpenCode can edit files and run commands in this project.',
                  style: TextStyle(
                    color: OrbitColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),

          // Prompt Input
          const Text(
            'TASK PROMPT',
            style: TextStyle(
              color: OrbitColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _promptController,
            maxLines: 7,
            minLines: 4,
            style: const TextStyle(
              color: OrbitColors.textPrimary,
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: _selectedAgent == AiAgent.plan
                  ? 'e.g. Inspect architecture and list areas for improvement...'
                  : 'e.g. Fix the failing test in parser_test.dart...',
              hintStyle: const TextStyle(
                color: OrbitColors.textMuted,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              filled: true,
              fillColor: OrbitColors.surfaceDark,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: OrbitColors.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: OrbitColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Start Button
          OrbitButton(
            text: _selectedAgent == AiAgent.plan ? 'Start Plan Task' : 'Start Build Task',
            icon: const Icon(Icons.play_arrow, size: 18),
            isLoading: state.isLoading,
            onPressed: _startTask,
          ),
        ],
      ),
    );
  }

  Widget _buildModeOption({
    required AiAgent agent,
    required String title,
    required String subtitle,
    required bool isSelected,
    required Color color,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAgent = agent;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : OrbitColors.surfaceDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : OrbitColors.borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? color : OrbitColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  Icon(Icons.check_circle, size: 15, color: color),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
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
  }
}
