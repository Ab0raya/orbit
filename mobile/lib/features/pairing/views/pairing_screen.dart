import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_button.dart';
import '../../../shared/widgets/orbit_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../controllers/pairing_controller.dart';
import '../../navigation/views/main_navigation_shell.dart';

class PairingScreen extends ConsumerStatefulWidget {
  final String host;
  final int port;
  final String? initialCode;

  const PairingScreen({
    super.key,
    required this.host,
    required this.port,
    this.initialCode,
  });

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final List<TextEditingController> _digitControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null && widget.initialCode!.isNotEmpty) {
      final chars = widget.initialCode!.replaceAll(RegExp(r'\s+'), '').split('');
      for (var i = 0; i < 6 && i < chars.length; i++) {
        _digitControllers[i].text = chars[i];
      }
      if (chars.length == 6) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handlePair();
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String _getCode() {
    return _digitControllers.map((c) => c.text).join();
  }

  Future<void> _handlePair() async {
    final code = _getCode();
    ref.read(pairingControllerProvider.notifier).setCode(code);

    final success = await ref
        .read(pairingControllerProvider.notifier)
        .verifyPairing(widget.host, widget.port);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainNavigationShell(host: widget.host, port: widget.port),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pairingControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair Device', style: TextStyle(fontSize: 16)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              // Status Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StatusPill(
                    label: 'Connected to ${widget.host}:${widget.port} (Unpaired)',
                    type: StatusType.warning,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: OrbitColors.orbitSurfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: OrbitColors.orbitBorder),
                  ),
                  child: const Icon(
                    Icons.security,
                    color: OrbitColors.orbitAccent,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Pair with Orbit Desktop',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: OrbitColors.orbitTextPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Enter the 6-digit code displayed on your PC screen',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: OrbitColors.orbitTextSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Error Banner
              if (state.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: OrbitColors.orbitError.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: OrbitColors.orbitError.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: OrbitColors.orbitError, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.errorMessage!,
                          style: const TextStyle(
                            color: OrbitColors.orbitError,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // 6-digit PIN Boxes Card
              OrbitCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(6, (index) {
                        return SizedBox(
                          width: 44,
                          height: 52,
                          child: TextField(
                            controller: _digitControllers[index],
                            focusNode: _focusNodes[index],
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(1),
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: OrbitColors.orbitAccent,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              filled: true,
                              fillColor: OrbitColors.orbitBackground,
                              contentPadding: EdgeInsets.zero,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: OrbitColors.orbitBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: OrbitColors.orbitAccent, width: 2),
                              ),
                            ),
                            onChanged: (val) {
                              if (val.isNotEmpty) {
                                if (index < 5) {
                                  _focusNodes[index + 1].requestFocus();
                                } else {
                                  _focusNodes[index].unfocus();
                                  _handlePair();
                                }
                              } else if (index > 0) {
                                _focusNodes[index - 1].requestFocus();
                              }
                            },
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),
                    OrbitButton(
                      label: state.isPairing ? 'Pairing...' : 'Pair Device',
                      isLoading: state.isPairing,
                      onPressed: state.isPairing ? null : () => _handlePair(),
                      width: double.infinity,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'Codes expire every 10 minutes. Regenerate on PC if expired.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: OrbitColors.orbitTextTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
