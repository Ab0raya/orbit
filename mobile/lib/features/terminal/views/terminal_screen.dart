import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../protocol/models/terminal_models.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../controllers/terminal_controller.dart';
import 'command_toolbox_screen.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';

const orbitTerminalTheme = TerminalTheme(
  cursor: Color(0xCCFFFFFF),
  selection: Color(0x33FFFFFF),
  foreground: Color(0xFFE6EDF3),
  background: Color(0xFF000000),
  black: Color(0xFF0A0A0A),
  red: Color(0xFFFF6B6B),
  green: Color(0xFF10B981),
  yellow: Color(0xFFF2CC60),
  blue: Color(0xFF79C0FF),
  magenta: Color(0xFFD2A8FF),
  cyan: Color(0xFF56D4DD),
  white: Color(0xFFE6EDF3),
  brightBlack: Color(0xFF555555),
  brightRed: Color(0xFFFF7B72),
  brightGreen: Color(0xFF10B981),
  brightYellow: Color(0xFFF2CC60),
  brightBlue: Color(0xFF79C0FF),
  brightMagenta: Color(0xFFD2A8FF),
  brightCyan: Color(0xFF56D4DD),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFF222222),
  searchHitBackgroundCurrent: Color(0xFFFFFFFF),
  searchHitForeground: Color(0xFF000000),
);

class TerminalScreen extends ConsumerStatefulWidget {
  final String? initialCwd;
  final String? initialCommand;
  final String? runningScriptName;
  final VoidCallback? onBack;

  const TerminalScreen({
    super.key,
    this.initialCwd,
    this.initialCommand,
    this.runningScriptName,
    this.onBack,
  });

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final FocusNode _terminalFocusNode = FocusNode();
  TerminalCursorType _cursorType = TerminalCursorType.verticalBar;
  final TextInputType _keyboardType = TextInputType.visiblePassword;

  @override
  void initState() {
    super.initState();
    if (widget.initialCwd != null || widget.initialCommand != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final notifier = ref.read(terminalControllerProvider.notifier);
        await notifier.createSession(cwd: widget.initialCwd);
        if (widget.initialCommand != null && widget.initialCommand!.isNotEmpty) {
          final cmd = widget.initialCommand!.endsWith('\n')
              ? widget.initialCommand!
              : '${widget.initialCommand!}\n';
          await notifier.sendInput(cmd);
        }
      });
    }
  }

  @override
  void dispose() {
    _terminalFocusNode.dispose();
    super.dispose();
  }

  void _sendSpecialKey(String key) {
    final notifier = ref.read(terminalControllerProvider.notifier);
    switch (key) {
      case 'Ctrl+C':
        notifier.sendInput('\x03');
        break;
      case 'Ctrl+D':
        notifier.sendInput('\x04');
        break;
      case 'Ctrl+L':
        notifier.sendInput('\x0c');
        break;
      case 'Tab':
        notifier.sendInput('\t');
        break;
      case 'Esc':
        notifier.sendInput('\x1b');
        break;
      case 'Up':
        notifier.sendInput('\x1b[A');
        break;
      case 'Down':
        notifier.sendInput('\x1b[B');
        break;
      case 'Left':
        notifier.sendInput('\x1b[D');
        break;
      case 'Right':
        notifier.sendInput('\x1b[C');
        break;
      case 'Home':
        notifier.sendInput('\x1b[H');
        break;
      case 'End':
        notifier.sendInput('\x1b[F');
        break;
      case 'PgUp':
        notifier.sendInput('\x1b[5~');
        break;
      case 'PgDn':
        notifier.sendInput('\x1b[6~');
        break;
      case 'Clear':
        notifier.clearLocalBuffer();
        break;
    }
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      ref.read(terminalControllerProvider.notifier).sendInput(text);
    }
  }

  void _showMoreKeysSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            const Text(
              'EXTENDED SHORTCUTS',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: OrbitColors.orbitTextMuted,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildKeyPill('Ctrl+C', () {
                  Navigator.pop(ctx);
                  _sendSpecialKey('Ctrl+C');
                }, isDanger: true),
                _buildKeyPill('Ctrl+D', () {
                  Navigator.pop(ctx);
                  _sendSpecialKey('Ctrl+D');
                }),
                _buildKeyPill('Ctrl+L', () {
                  Navigator.pop(ctx);
                  _sendSpecialKey('Ctrl+L');
                }),
                _buildKeyPill('Home', () {
                  Navigator.pop(ctx);
                  _sendSpecialKey('Home');
                }),
                _buildKeyPill('End', () {
                  Navigator.pop(ctx);
                  _sendSpecialKey('End');
                }),
                _buildKeyPill('PgUp', () {
                  Navigator.pop(ctx);
                  _sendSpecialKey('PgUp');
                }),
                _buildKeyPill('PgDn', () {
                  Navigator.pop(ctx);
                  _sendSpecialKey('PgDn');
                }),
                _buildKeyPill('PASTE', () {
                  Navigator.pop(ctx);
                  _handlePaste();
                }),
                _buildKeyPill('CLEAR', () {
                  Navigator.pop(ctx);
                  _sendSpecialKey('Clear');
                }),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCloseSession(
    BuildContext context,
    String sessionId, {
    String? title,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: OrbitColors.orbitBorder),
        ),
        title: const Text(
          'Close Terminal Session?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          title != null
              ? 'This will terminate session "$title" and kill any running processes in it.'
              : 'This will terminate this terminal session and kill any running processes in it.',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: OrbitColors.orbitError,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(terminalControllerProvider.notifier).killSession(sessionId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(terminalControllerProvider);
    final notifier = ref.read(terminalControllerProvider.notifier);
    TerminalSessionSummary? currentSession;
    for (final s in state.sessions) {
      if (s.sessionId == state.activeSessionId) {
        currentSession = s;
        break;
      }
    }
    currentSession ??= state.sessions.isNotEmpty ? state.sessions.first : null;

    final isConnected = state.activeSessionId != null && !state.isExited;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: OrbitColors.orbitSurface,
        elevation: 0,
        leading: (widget.onBack != null || Navigator.of(context).canPop())
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                tooltip: 'Back',
                onPressed: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              )
            : null,
        titleSpacing: (widget.onBack != null || Navigator.of(context).canPop()) ? null : 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: OrbitColors.orbitBorder),
              ),
              child: const Text(
                '>_',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'ORBIT / TERMINAL',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.runningScriptName != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16251C),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF1D5A36)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: Color(0xFF10B981), size: 12),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          widget.runningScriptName!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Command Toolbox Button
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: InkWell(
              key: const Key('terminal_toolbox_button'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const CommandToolboxScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: OrbitColors.orbitBorder),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 13,
                      color: OrbitColors.orbitAccentCyan,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Tools',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Connected Pill
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: OrbitColors.orbitBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected ? const Color(0xFF10B981) : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isConnected
                        ? 'Connected'
                        : (state.isExited ? 'Exited' : 'Idle'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
              size: 18,
              color: Colors.white70,
            ),
            color: const Color(0xFF141414),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: OrbitColors.orbitBorder),
            ),
            onSelected: (val) {
              if (val == 'clear') {
                notifier.clearLocalBuffer();
              } else if (val == 'kill') {
                if (currentSession != null) {
                  _confirmCloseSession(
                    context,
                    currentSession.sessionId,
                    title: '#${state.sessions.indexOf(currentSession) + 1} ${currentSession.shell.split("/").last}',
                  );
                }
              } else if (val == 'refresh') {
                notifier.listSessions();
              } else if (val == 'cursor_bar') {
                setState(() => _cursorType = TerminalCursorType.verticalBar);
              } else if (val == 'cursor_underline') {
                setState(() => _cursorType = TerminalCursorType.underline);
              } else if (val == 'cursor_block') {
                setState(() => _cursorType = TerminalCursorType.block);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'cursor_bar',
                child: Row(
                  children: [
                    Icon(
                      Icons.format_align_left_rounded,
                      size: 16,
                      color: _cursorType == TerminalCursorType.verticalBar
                          ? OrbitColors.orbitAccent
                          : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cursor: Vertical Bar (I-Beam)',
                      style: TextStyle(
                        fontSize: 12,
                        color: _cursorType == TerminalCursorType.verticalBar
                            ? OrbitColors.orbitAccent
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'cursor_underline',
                child: Row(
                  children: [
                    Icon(
                      Icons.horizontal_rule_rounded,
                      size: 16,
                      color: _cursorType == TerminalCursorType.underline
                          ? OrbitColors.orbitAccent
                          : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cursor: Underline',
                      style: TextStyle(
                        fontSize: 12,
                        color: _cursorType == TerminalCursorType.underline
                            ? OrbitColors.orbitAccent
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'cursor_block',
                child: Row(
                  children: [
                    Icon(
                      Icons.check_box_outline_blank_rounded,
                      size: 16,
                      color: _cursorType == TerminalCursorType.block
                          ? OrbitColors.orbitAccent
                          : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cursor: Block',
                      style: TextStyle(
                        fontSize: 12,
                        color: _cursorType == TerminalCursorType.block
                            ? OrbitColors.orbitAccent
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(
                      Icons.clear_all_rounded,
                      size: 16,
                      color: Colors.white70,
                    ),
                    SizedBox(width: 8),
                    Text('Clear Screen', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: Colors.white70,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Refresh Sessions',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'kill',
                child: Row(
                  children: [
                    Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: OrbitColors.orbitError,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Close Terminal',
                      style: TextStyle(color: OrbitColors.orbitError),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Subheader: Path & New Session Button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF000000),
                border: Border(
                  bottom: BorderSide(color: OrbitColors.orbitBorder),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      currentSession?.cwd ?? '/home/aburaya',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFFA1A1AA),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: Colors.white70,
                    ),
                    tooltip: 'Copy current path',
                    onPressed: () {
                      final path = currentSession?.cwd ?? '';
                      if (path.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: path));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Path copied to clipboard'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 20, color: Colors.white),
                    tooltip: 'New Terminal Session',
                    onPressed: () => notifier.createSession(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  if (currentSession != null) ...[
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: Colors.white70,
                      ),
                      tooltip: 'Close Current Terminal',
                      onPressed: () {
                        final session = currentSession;
                        if (session != null) {
                          _confirmCloseSession(
                            context,
                            session.sessionId,
                            title: '#${state.sessions.indexOf(session) + 1} ${session.shell.split("/").last}',
                          );
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Error banner if any
            if (state.errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                color: OrbitColors.orbitError.withValues(alpha: 0.15),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 14,
                      color: OrbitColors.orbitError,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: OrbitColors.orbitError,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Multiple Session Selector Tabs (if more than 1 session)
            if (state.sessions.length > 1)
              Container(
                height: 34,
                color: const Color(0xFF0A0A0A),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.sessions.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 6),
                  itemBuilder: (context, idx) {
                    final s = state.sessions[idx];
                    final isSelected = s.sessionId == state.activeSessionId;
                    final tabLabel = '#${idx + 1} ${s.shell.split("/").last}';
                    return Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF1E1E1E)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected
                              ? Colors.white24
                              : OrbitColors.orbitBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => notifier.selectSession(s.sessionId),
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 8,
                                top: 4,
                                bottom: 4,
                                right: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: s.isRunning
                                          ? const Color(0xFF10B981)
                                          : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    tabLabel,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white60,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _confirmCloseSession(
                              context,
                              s.sessionId,
                              title: tabLabel,
                            ),
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: isSelected
                                    ? Colors.white70
                                    : Colors.white38,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            // Main Terminal Canvas
            Expanded(
              child: state.isLoading && state.activeSessionId == null
                  ? const Center(child: OrbitLoadingIndicator(size: 40))
                  : state.sessions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.terminal_rounded,
                                size: 44,
                                color: Colors.white24,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No Active Terminal Sessions',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Create a new session to run shell commands.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: OrbitColors.orbitTextMuted,
                                ),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: () => notifier.createSession(),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('New Session'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: OrbitColors.orbitBorder),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          color: const Color(0xFF000000),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: TerminalView(
                            notifier.terminal,
                            theme: orbitTerminalTheme,
                            autofocus: true,
                            focusNode: _terminalFocusNode,
                            cursorType: _cursorType,
                            keyboardType: _keyboardType,
                            deleteDetection: true,
                            onKeyEvent: (focusNode, event) {
                              if (event is KeyDownEvent) {
                                if (event.logicalKey == LogicalKeyboardKey.enter ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.numpadEnter) {
                                  notifier.sendInput('\r');
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            textStyle: const TerminalStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
            ),

            // Mobile Developer Shortcut Bar matching Screen 5 in reference
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: const BoxDecoration(
                color: Color(0xFF0C0C0C),
                border: Border(
                  top: BorderSide(color: OrbitColors.orbitBorder, width: 1),
                ),
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // Sticky CTRL key toggle
                  _buildCtrlKeyPill(
                    isActive: state.isCtrlActive,
                    onTap: () => notifier.toggleCtrl(),
                  ),
                  _buildKeyPill('RETURN', () => notifier.sendInput('\r')),
                  _buildKeyPill('TAB', () => _sendSpecialKey('Tab')),
                  _buildKeyPill('ESC', () => _sendSpecialKey('Esc')),
                  _buildKeyPill('/', () => notifier.sendInput('/')),
                  _buildKeyPill('|', () => notifier.sendInput('|')),
                  _buildKeyPill('-', () => notifier.sendInput('-')),
                  _buildKeyPill('...', () => _showMoreKeysSheet(context)),
                  _buildKeyPill('↑', () => _sendSpecialKey('Up')),
                  _buildKeyPill('↓', () => _sendSpecialKey('Down')),
                  _buildKeyPill('←', () => _sendSpecialKey('Left')),
                  _buildKeyPill('→', () => _sendSpecialKey('Right')),
                  _buildKeyPill(
                    'Ctrl+C',
                    () => _sendSpecialKey('Ctrl+C'),
                    isDanger: true,
                  ),
                  _buildKeyPill('Ctrl+D', () => _sendSpecialKey('Ctrl+D')),
                  _buildKeyPill('Ctrl+L', () => _sendSpecialKey('Ctrl+L')),
                  _buildKeyPill('PASTE', _handlePaste),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCtrlKeyPill({
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF262626)
                  : const Color(0xFF141414),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isActive ? Colors.white : OrbitColors.orbitBorder,
                width: isActive ? 1.4 : 1.0,
              ),
            ),
            child: Center(
              child: Text(
                'CTRL',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.white : Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyPill(
    String label,
    VoidCallback onTap, {
    bool isDanger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: isDanger
                  ? OrbitColors.orbitError.withValues(alpha: 0.15)
                  : const Color(0xFF141414),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isDanger
                    ? OrbitColors.orbitError.withValues(alpha: 0.5)
                    : OrbitColors.orbitBorder,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDanger ? OrbitColors.orbitError : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
