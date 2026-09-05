import 'package:flutter/material.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_button.dart';
import '../models/project_models.dart';

class BranchSelectorSheet extends StatelessWidget {
  final GitBranches branches;
  final ValueChanged<String> onSelectBranch;
  final ValueChanged<String> onCreateBranch;

  const BranchSelectorSheet({
    super.key,
    required this.branches,
    required this.onSelectBranch,
    required this.onCreateBranch,
  });

  static Future<void> show(
    BuildContext context, {
    required GitBranches branches,
    required ValueChanged<String> onSelectBranch,
    required ValueChanged<String> onCreateBranch,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: OrbitColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => BranchSelectorSheet(
        branches: branches,
        onSelectBranch: onSelectBranch,
        onCreateBranch: onCreateBranch,
      ),
    );
  }

  void _promptCreateBranch(BuildContext context) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OrbitColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: OrbitColors.borderSubtle),
        ),
        title: const Text(
          'NEW BRANCH',
          style: TextStyle(
            color: OrbitColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(
            color: OrbitColors.textPrimary,
            fontFamily: 'monospace',
          ),
          decoration: const InputDecoration(
            hintText: 'feature/branch-name',
            hintStyle: TextStyle(color: OrbitColors.textMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: OrbitColors.borderSubtle),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: OrbitColors.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: OrbitColors.textMuted)),
          ),
          OrbitButton(
            text: 'Create',
            onPressed: () {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                onCreateBranch(name);
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: OrbitColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Title & New branch action
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'BRANCHES',
                    style: TextStyle(
                      color: OrbitColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 1.1,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _promptCreateBranch(context);
                    },
                    icon: const Icon(Icons.add,
                        color: OrbitColors.primary, size: 16),
                    label: const Text(
                      'New Branch',
                      style: TextStyle(
                        color: OrbitColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: OrbitColors.borderSubtle),

            // Branch lists
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // Local branches
                  if (branches.local.isNotEmpty) ...[
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text(
                        'LOCAL',
                        style: TextStyle(
                          color: OrbitColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    ...branches.local.map((b) {
                      final isCurrent = b == branches.current;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.fork_right,
                          color: isCurrent
                              ? OrbitColors.primary
                              : OrbitColors.textMuted,
                          size: 18,
                        ),
                        title: Text(
                          b,
                          style: TextStyle(
                            color: isCurrent
                                ? OrbitColors.primary
                                : OrbitColors.textPrimary,
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontFamily: 'monospace',
                          ),
                        ),
                        trailing: isCurrent
                            ? const Icon(Icons.check,
                                color: OrbitColors.primary, size: 18)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          if (!isCurrent) {
                            onSelectBranch(b);
                          }
                        },
                      );
                    }),
                  ],

                  // Remote branches
                  if (branches.remote.isNotEmpty) ...[
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text(
                        'REMOTE',
                        style: TextStyle(
                          color: OrbitColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    ...branches.remote.map((b) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.cloud_outlined,
                          color: OrbitColors.textMuted,
                          size: 18,
                        ),
                        title: Text(
                          b,
                          style: const TextStyle(
                            color: OrbitColors.textMuted,
                            fontFamily: 'monospace',
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onSelectBranch(b);
                        },
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
