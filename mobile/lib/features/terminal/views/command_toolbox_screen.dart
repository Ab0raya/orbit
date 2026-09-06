import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../controllers/terminal_controller.dart';
import '../models/command_tool.dart';

class CommandToolboxScreen extends ConsumerStatefulWidget {
  final String? initialOs;

  const CommandToolboxScreen({
    super.key,
    this.initialOs,
  });

  @override
  ConsumerState<CommandToolboxScreen> createState() => _CommandToolboxScreenState();
}

class _CommandToolboxScreenState extends ConsumerState<CommandToolboxScreen> {
  final TextEditingController _searchController = TextEditingController();
  TargetOs _detectedOs = TargetOs.linux;
  String _osDisplayName = 'Linux';
  CommandCategory? _selectedCategory;
  final List<String> _recentToolIds = [];
  bool _isCaffeinateActive = false;
  String? _scheduledShutdownTime;
  Timer? _shutdownTimer;

  @override
  void initState() {
    super.initState();
    _detectOs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(terminalControllerProvider.notifier);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _shutdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _detectOs() async {
    if (widget.initialOs != null) {
      _applyOs(widget.initialOs!);
      return;
    }

    try {
      final client = ref.read(webSocketClientProvider);
      final res = await client.sendRequest('system.info');
      if (res.success && res.payload != null) {
        final rawOs = res.payload!['os'] as String? ?? '';
        if (mounted) {
          _applyOs(rawOs);
        }
      }
    } catch (_) {
      if (mounted) {
        _applyOs('Linux');
      }
    }
  }

  void _applyOs(String rawOs) {
    setState(() {
      _detectedOs = TargetOs.fromString(rawOs);
      _osDisplayName = rawOs.isNotEmpty ? rawOs : _detectedOs.name.toUpperCase();
    });
  }

  void _executeCommand(String command, {String? toolId, bool pop = false}) {
    if (toolId != null) {
      setState(() {
        _recentToolIds.remove(toolId);
        _recentToolIds.insert(0, toolId);
        if (_recentToolIds.length > 5) {
          _recentToolIds.removeLast();
        }
      });
    }

    // Send command to active terminal session with Carriage Return
    final normalized = command.endsWith('\r') || command.endsWith('\n')
        ? command
        : '$command\r';
    ref.read(terminalControllerProvider.notifier).sendInput(normalized);

    if (pop && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.terminal_rounded, color: OrbitColors.orbitAccentCyan, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Executed: $command',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Open Terminal',
          textColor: OrbitColors.orbitAccentCyan,
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        backgroundColor: OrbitColors.orbitCard,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: OrbitColors.orbitBorder),
        ),
      ),
    );
  }

  void _handleToolTap(CommandTool tool) {
    switch (tool.executionType) {
      case CommandExecutionType.instant:
        final cmd = tool.buildCommand(_detectedOs);
        _executeCommand(cmd, toolId: tool.id);
        break;

      case CommandExecutionType.confirmation:
        _showConfirmationDialog(tool);
        break;

      case CommandExecutionType.parameterized:
        _showParameterizedDialog(tool);
        break;

      case CommandExecutionType.powerTimer:
        _showShutdownTimerDialog(tool);
        break;

      case CommandExecutionType.toggle:
        _handleToggleTool(tool);
        break;
    }
  }

  void _showConfirmationDialog(CommandTool tool) {
    final cmd = tool.buildCommand(_detectedOs);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: OrbitColors.orbitBorder),
        ),
        title: Text(
          tool.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tool.description,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: OrbitColors.orbitBorder),
              ),
              child: Text(
                cmd,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: OrbitColors.orbitAccentCyan,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tool.dangerLevel == DangerLevel.destructive
                  ? OrbitColors.orbitError
                  : OrbitColors.orbitAccentCyan,
              foregroundColor: tool.dangerLevel == DangerLevel.destructive
                  ? Colors.white
                  : Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _executeCommand(cmd, toolId: tool.id);
            },
            child: const Text('Confirm & Run'),
          ),
        ],
      ),
    );
  }

  void _showParameterizedDialog(CommandTool tool) {
    final Map<String, TextEditingController> controllers = {};
    for (final field in tool.inputFields) {
      controllers[field.key] = TextEditingController(text: field.defaultValue ?? '');
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final currentParams = controllers.map((k, v) => MapEntry(k, v.text));
          final previewCmd = tool.buildCommand(_detectedOs, currentParams);

          return AlertDialog(
            backgroundColor: const Color(0xFF141414),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: OrbitColors.orbitBorder),
            ),
            title: Text(
              tool.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool.description,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  ...tool.inputFields.map((field) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            field.label,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              color: OrbitColors.orbitTextMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: controllers[field.key],
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            keyboardType: field.isNumeric ? TextInputType.number : TextInputType.text,
                            decoration: InputDecoration(
                              hintText: field.hint,
                              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                              filled: true,
                              fillColor: const Color(0xFF0A0A0A),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: OrbitColors.orbitBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: OrbitColors.orbitAccentCyan),
                              ),
                            ),
                            onChanged: (_) => setModalState(() {}),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                  const Text(
                    'Command Preview',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: OrbitColors.orbitTextMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: OrbitColors.orbitBorder),
                    ),
                    child: Text(
                      previewCmd,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: OrbitColors.orbitAccentCyan,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tool.dangerLevel == DangerLevel.destructive
                      ? OrbitColors.orbitError
                      : OrbitColors.orbitAccentCyan,
                  foregroundColor: tool.dangerLevel == DangerLevel.destructive
                      ? Colors.white
                      : Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _executeCommand(previewCmd, toolId: tool.id);
                },
                child: Text('Run ${tool.title}'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showShutdownTimerDialog(CommandTool tool) {
    int selectedMinutes = 0;
    final customController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final cmd = tool.buildCommand(_detectedOs, {'minutes': selectedMinutes.toString()});

          return AlertDialog(
            backgroundColor: const Color(0xFF141414),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: OrbitColors.orbitBorder),
            ),
            title: const Row(
              children: [
                Icon(Icons.power_settings_new_rounded, color: OrbitColors.orbitError, size: 20),
                SizedBox(width: 8),
                Text(
                  'SHUTDOWN PC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WHEN SHOULD THIS PC SHUT DOWN?',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    color: OrbitColors.orbitTextMuted,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildTimerOption('Immediately', 0, selectedMinutes, (m) {
                      setModalState(() => selectedMinutes = m);
                    }),
                    _buildTimerOption('5 minutes', 5, selectedMinutes, (m) {
                      setModalState(() => selectedMinutes = m);
                    }),
                    _buildTimerOption('10 minutes', 10, selectedMinutes, (m) {
                      setModalState(() => selectedMinutes = m);
                    }),
                    _buildTimerOption('30 minutes', 30, selectedMinutes, (m) {
                      setModalState(() => selectedMinutes = m);
                    }),
                    _buildTimerOption('1 hour', 60, selectedMinutes, (m) {
                      setModalState(() => selectedMinutes = m);
                    }),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text(
                      'Custom (mins):',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: customController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'e.g. 45',
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.black,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: OrbitColors.orbitBorder),
                          ),
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val.trim());
                          if (parsed != null && parsed >= 0) {
                            setModalState(() => selectedMinutes = parsed);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: OrbitColors.orbitBorder),
                  ),
                  child: Text(
                    cmd,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: OrbitColors.orbitError,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: OrbitColors.orbitError,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  if (selectedMinutes > 0) {
                    _scheduleShutdownBanner(selectedMinutes);
                  }
                  _executeCommand(cmd, toolId: tool.id);
                },
                child: Text(
                  selectedMinutes == 0 ? 'Shutdown Now' : 'Schedule Shutdown',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _scheduleShutdownBanner(int minutes) {
    setState(() {
      _scheduledShutdownTime = '$minutes:00';
    });
  }

  Widget _buildTimerOption(
    String label,
    int minutes,
    int selectedMinutes,
    ValueChanged<int> onSelect,
  ) {
    final isSelected = selectedMinutes == minutes;
    return InkWell(
      onTap: () => onSelect(minutes),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.white : OrbitColors.orbitBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
            color: isSelected ? Colors.black : Colors.white70,
          ),
        ),
      ),
    );
  }

  void _handleToggleTool(CommandTool tool) {
    final action = _isCaffeinateActive ? 'stop' : 'start';
    final cmd = tool.buildCommand(_detectedOs, {'action': action});
    setState(() {
      _isCaffeinateActive = !_isCaffeinateActive;
    });
    _executeCommand(cmd, toolId: tool.id);
  }

  List<CommandTool> _getFilteredTools() {
    final query = _searchController.text.trim().toLowerCase();

    return builtInCommandTools.where((t) {
      if (!t.isSupportedOn(_detectedOs)) return false;
      if (_selectedCategory != null && t.category != _selectedCategory) return false;
      if (query.isNotEmpty) {
        final matchesTitle = t.title.toLowerCase().contains(query);
        final matchesDesc = t.description.toLowerCase().contains(query);
        final matchesCat = t.category.label.toLowerCase().contains(query);
        return matchesTitle || matchesDesc || matchesCat;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredTools = _getFilteredTools();
    final recentTools = _recentToolIds
        .map((id) => builtInCommandTools.firstWhere(
              (t) => t.id == id,
              orElse: () => builtInCommandTools.first,
            ))
        .where((t) => t.isSupportedOn(_detectedOs))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: OrbitColors.orbitSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          tooltip: 'Back to Terminal',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: OrbitColors.orbitBorder),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                size: 13,
                color: OrbitColors.orbitAccentCyan,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'COMMAND TOOLBOX',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: OrbitColors.orbitBorder),
                ),
                child: Text(
                  _osDisplayName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: OrbitColors.orbitAccentCyan,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Scheduled Shutdown Banner (if active)
          if (_scheduledShutdownTime != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: OrbitColors.orbitError.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 16, color: OrbitColors.orbitError),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'SHUTDOWN SCHEDULED',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: OrbitColors.orbitError,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      final cancelTool = builtInCommandTools.firstWhere((t) => t.id == 'shutdown_cancel');
                      final cmd = cancelTool.buildCommand(_detectedOs);
                      setState(() => _scheduledShutdownTime = null);
                      _executeCommand(cmd, toolId: cancelTool.id);
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: OrbitColors.orbitError,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Cancel Shutdown',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Search Field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: OrbitColors.orbitBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 16, color: OrbitColors.orbitTextMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Search commands & tools...',
                        hintStyle: TextStyle(
                          color: OrbitColors.orbitTextMuted,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 14, color: Colors.white54),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
          ),

          // Category Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _buildCategoryChip('All', null),
                ...CommandCategory.values.map((cat) => _buildCategoryChip(cat.label, cat)),
              ],
            ),
          ),

          const Divider(color: OrbitColors.orbitBorder, height: 16),

          // Command Tools List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // Recent Section
                if (recentTools.isNotEmpty && _searchController.text.isEmpty && _selectedCategory == null) ...[
                  const Text(
                    'RECENT',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: OrbitColors.orbitTextMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...recentTools.map((t) => _buildToolCard(t)),
                  const SizedBox(height: 16),
                ],

                // Filtered Tools List
                if (filteredTools.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    alignment: Alignment.center,
                    child: const Text(
                      'No matching tools found',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: OrbitColors.orbitTextMuted,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  ...filteredTools.map((t) => _buildToolCard(t)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, CommandCategory? category) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() => _selectedCategory = category),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : const Color(0xFF141414),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? Colors.white : OrbitColors.orbitBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.black : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolCard(CommandTool tool) {
    final previewCmd = tool.buildCommand(_detectedOs);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _handleToolTap(tool),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: OrbitColors.orbitBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: tool.dangerLevel == DangerLevel.destructive
                      ? OrbitColors.orbitError.withValues(alpha: 0.15)
                      : const Color(0xFF161616),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: tool.dangerLevel == DangerLevel.destructive
                        ? OrbitColors.orbitError.withValues(alpha: 0.4)
                        : OrbitColors.orbitBorder,
                  ),
                ),
                child: Icon(
                  tool.icon,
                  size: 16,
                  color: tool.dangerLevel == DangerLevel.destructive
                      ? OrbitColors.orbitError
                      : Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tool.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (tool.executionType == CommandExecutionType.parameterized)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: OrbitColors.orbitBorder),
                            ),
                            child: const Text(
                              'FORM',
                              style: TextStyle(
                                fontSize: 9,
                                fontFamily: 'monospace',
                                color: OrbitColors.orbitAccentCyan,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else if (tool.executionType == CommandExecutionType.powerTimer)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF221111),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: OrbitColors.orbitError),
                            ),
                            child: const Text(
                              'TIMER',
                              style: TextStyle(
                                fontSize: 9,
                                fontFamily: 'monospace',
                                color: OrbitColors.orbitError,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tool.description,
                      style: const TextStyle(
                        fontSize: 11,
                        color: OrbitColors.orbitTextMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF050505),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        previewCmd,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          color: OrbitColors.orbitTextMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Center(
                child: IconButton(
                  icon: const Icon(Icons.play_arrow_rounded, color: OrbitColors.orbitAccentCyan, size: 20),
                  tooltip: 'Run ${tool.title}',
                  onPressed: () => _handleToolTap(tool),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
