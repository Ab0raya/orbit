import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart' as xterm;
import '../../../core/networking/orbit_websocket_client.dart';
import '../../../core/providers.dart';
import '../../../protocol/models/terminal_models.dart';

class TerminalState {
  final bool isLoading;
  final String? activeSessionId;
  final List<TerminalSessionSummary> sessions;
  final String? errorMessage;
  final bool isExited;
  final int? exitCode;
  final int cols;
  final int rows;
  final bool isCtrlActive;

  const TerminalState({
    this.isLoading = false,
    this.activeSessionId,
    this.sessions = const [],
    this.errorMessage,
    this.isExited = false,
    this.exitCode,
    this.cols = 80,
    this.rows = 24,
    this.isCtrlActive = false,
  });

  TerminalState copyWith({
    bool? isLoading,
    String? activeSessionId,
    List<TerminalSessionSummary>? sessions,
    String? errorMessage,
    bool? isExited,
    int? exitCode,
    int? cols,
    int? rows,
    bool? isCtrlActive,
    bool clearError = false,
    bool clearActiveSession = false,
  }) {
    return TerminalState(
      isLoading: isLoading ?? this.isLoading,
      activeSessionId: clearActiveSession
          ? null
          : (activeSessionId ?? this.activeSessionId),
      sessions: sessions ?? this.sessions,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isExited: isExited ?? this.isExited,
      exitCode: exitCode ?? this.exitCode,
      cols: cols ?? this.cols,
      rows: rows ?? this.rows,
      isCtrlActive: isCtrlActive ?? this.isCtrlActive,
    );
  }
}

class TerminalController extends StateNotifier<TerminalState> {
  final OrbitWebSocketClient _client;
  final xterm.Terminal terminal = xterm.Terminal(maxLines: 10000);
  StreamSubscription? _eventsSubscription;
  Timer? _resizeDebounce;

  TerminalController(this._client) : super(const TerminalState()) {
    _setupTerminalCallbacks();
    _subscribeToEvents();
    initTerminal();
  }

  void _setupTerminalCallbacks() {
    terminal.onOutput = (data) {
      if (state.isCtrlActive && data.isNotEmpty) {
        state = state.copyWith(isCtrlActive: false);
        final firstChar = data[0].toUpperCase();
        final code = firstChar.codeUnitAt(0);
        if (code >= 64 && code <= 95) {
          final ctrlByte = String.fromCharCode(code - 64);
          final remainder = data.length > 1 ? data.substring(1) : '';
          sendInput(ctrlByte + remainder);
          return;
        }
      }

      // Interactive CLI programs (e.g. agy, vim) running in raw mode expect \r for Enter
      String normalized = data;
      if (normalized == '\n') {
        normalized = '\r';
      } else if (normalized.endsWith('\n') && !normalized.endsWith('\r\n')) {
        normalized = normalized.replaceAll('\n', '\r');
      }

      sendInput(normalized);
    };

    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      Future.microtask(() {
        if (mounted) {
          resize(width, height);
        }
      });
    };
  }

  void toggleCtrl() {
    state = state.copyWith(isCtrlActive: !state.isCtrlActive);
  }

  void setCtrl(bool active) {
    state = state.copyWith(isCtrlActive: active);
  }

  void _subscribeToEvents() {
    _eventsSubscription?.cancel();
    _eventsSubscription = _client.events.listen((event) {
      if (event.event == 'terminal.output') {
        final sid = event.payload['sessionId'] as String?;
        final data = event.payload['data'] as String?;
        if (sid == state.activeSessionId && data != null) {
          // Stream raw PTY bytes directly into the xterm emulator
          terminal.write(data);
        }
      } else if (event.event == 'terminal.exited') {
        final sid = event.payload['sessionId'] as String?;
        final code = event.payload['exitCode'] as int?;
        if (sid == state.activeSessionId) {
          state = state.copyWith(
            isExited: true,
            exitCode: code,
          );
          terminal.write('\r\n\x1b[90m[Process completed with exit code $code]\x1b[0m\r\n');
        }
      }
    });
  }

  Future<void> initTerminal() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await listSessions();
      if (!mounted) return;
      if (state.sessions.isNotEmpty) {
        // Attach to the most recent running session
        final running = state.sessions.firstWhere(
          (s) => s.isRunning,
          orElse: () => state.sessions.first,
        );
        await selectSession(running.sessionId);
      } else {
        // Create new session
        await createSession();
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to initialize terminal: $e',
      );
    }
  }

  Future<void> listSessions() async {
    final response = await _client.sendRequest('terminal.list');
    if (!mounted) return;
    if (response.success && response.payload != null) {
      final list = (response.payload!['sessions'] as List<dynamic>?)
              ?.map((e) =>
                  TerminalSessionSummary.fromJson(e as Map<String, dynamic>))
              .where((s) => !s.isExited)
              .toList() ??
          [];

      String? activeId = state.activeSessionId;
      if (activeId != null && !list.any((s) => s.sessionId == activeId)) {
        if (list.isNotEmpty) {
          activeId = list.firstWhere(
            (s) => s.isRunning,
            orElse: () => list.first,
          ).sessionId;
        } else {
          activeId = null;
        }
      } else if (activeId == null && list.isNotEmpty) {
        activeId = list.firstWhere(
          (s) => s.isRunning,
          orElse: () => list.first,
        ).sessionId;
      }

      final previousActiveId = state.activeSessionId;
      state = state.copyWith(
        sessions: list,
        activeSessionId: activeId,
        clearActiveSession: activeId == null,
        isExited: activeId == null,
        isLoading: false,
      );

      if (activeId != null && activeId != previousActiveId) {
        terminal.buffer.clear();
        await fetchHistory(activeId);
      } else if (activeId == null) {
        terminal.buffer.clear();
      }
    }
  }

  Future<void> createSession({String? cwd, int cols = 80, int rows = 24}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final payload = TerminalCreatePayload(cwd: cwd, cols: cols, rows: rows);
      final response = await _client.sendRequest(
        'terminal.create',
        payload: payload.toJson(),
      );
      if (!mounted) return;

      if (response.success && response.payload != null) {
        final sid = response.payload!['sessionId'] as String;
        state = state.copyWith(
          activeSessionId: sid,
          isExited: false,
          exitCode: null,
          cols: cols,
          rows: rows,
          isLoading: false,
        );
        terminal.buffer.clear();
        await listSessions();
        if (!mounted) return;
        await fetchHistory(sid);
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: response.error?.message ?? 'Failed to create terminal session',
        );
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to create terminal: $e',
      );
    }
  }

  Future<void> selectSession(String sessionId) async {
    state = state.copyWith(
      activeSessionId: sessionId,
      isExited: false,
      exitCode: null,
      clearError: true,
    );
    terminal.buffer.clear();
    await fetchHistory(sessionId);
  }

  Future<void> fetchHistory(String sessionId) async {
    try {
      final payload = TerminalHistoryPayload(sessionId: sessionId);
      final response = await _client.sendRequest(
        'terminal.history',
        payload: payload.toJson(),
      );
      if (!mounted) return;

      if (response.success && response.payload != null) {
        final history = response.payload!['data'] as String? ?? '';
        if (history.isNotEmpty && state.activeSessionId == sessionId) {
          terminal.write(history);
        }
      }
    } catch (_) {}
  }

  Future<void> sendInput(String text) async {
    final sessionId = state.activeSessionId ??
        (state.sessions.isNotEmpty ? state.sessions.first.sessionId : null);
    if (sessionId == null) return;
    try {
      final payload = TerminalInputPayload(
        sessionId: sessionId,
        data: text,
      );
      await _client.sendRequest(
        'terminal.input',
        payload: payload.toJson(),
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        errorMessage: 'Failed to send terminal input: $e',
      );
    }
  }

  void resize(int cols, int rows) {
    if (!mounted) return;
    if (state.activeSessionId == null) return;
    if (cols == state.cols && rows == state.rows) return;

    state = state.copyWith(cols: cols, rows: rows);

    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      try {
        final payload = TerminalResizePayload(
          sessionId: state.activeSessionId!,
          cols: cols,
          rows: rows,
        );
        await _client.sendRequest(
          'terminal.resize',
          payload: payload.toJson(),
        );
      } catch (_) {}
    });
  }

  Future<void> killSession(String sessionId) async {
    try {
      final payload = TerminalKillPayload(sessionId: sessionId);
      await _client.sendRequest('terminal.kill', payload: payload.toJson());

      // Optimistically update sessions list and activeSessionId
      final remaining =
          state.sessions.where((s) => s.sessionId != sessionId).toList();
      String? nextActiveId = state.activeSessionId;

      if (state.activeSessionId == sessionId) {
        if (remaining.isNotEmpty) {
          final next = remaining.firstWhere(
            (s) => s.isRunning,
            orElse: () => remaining.first,
          );
          nextActiveId = next.sessionId;
        } else {
          nextActiveId = null;
        }
      }

      state = state.copyWith(
        sessions: remaining,
        activeSessionId: nextActiveId,
        clearActiveSession: nextActiveId == null,
        isExited: nextActiveId == null,
      );

      terminal.buffer.clear();
      if (nextActiveId != null) {
        await fetchHistory(nextActiveId);
      }

      await listSessions();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to close terminal: $e');
    }
  }

  Future<void> killCurrentSession() async {
    if (state.activeSessionId == null) return;
    await killSession(state.activeSessionId!);
  }

  void clearLocalBuffer() {
    terminal.buffer.clear();
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    _resizeDebounce?.cancel();
    super.dispose();
  }
}

final terminalControllerProvider =
    StateNotifierProvider<TerminalController, TerminalState>((ref) {
  final client = ref.watch(webSocketClientProvider);
  return TerminalController(client);
});
