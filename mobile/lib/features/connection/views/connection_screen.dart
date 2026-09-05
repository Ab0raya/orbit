import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_button.dart';
import '../../../shared/widgets/orbit_card.dart';
import '../../../shared/widgets/orbit_text_field.dart';
import '../../../shared/widgets/orbit_logo_widget.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../core/providers.dart';
import '../../../core/networking/connection_manager.dart';
import '../controllers/connection_controller.dart';
import '../../pairing/views/pairing_screen.dart';
import '../../pairing/controllers/pairing_controller.dart';
import '../../navigation/views/main_navigation_shell.dart';
import 'qr_scanner_sheet.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  late final TextEditingController _hostController;
  late final TextEditingController _tailscaleHostController;
  late final TextEditingController _portController;

  bool _howItWorksExpanded = false;
  bool _showManualOverride = false;
  bool _showManualUnconfigured = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(connectionControllerProvider);
    _hostController = TextEditingController(text: state.host);
    _tailscaleHostController = TextEditingController(
      text: state.tailscaleHost ?? state.savedPairedDevice?.tailscaleAddress ?? '',
    );
    _portController = TextEditingController(text: state.port.toString());
  }

  @override
  void dispose() {
    _hostController.dispose();
    _tailscaleHostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect({
    String? customHost,
    int? customPort,
    String? prefillPairingCode,
    ConnectionPathType? specificPath,
  }) async {
    final state = ref.read(connectionControllerProvider);
    final path = specificPath ?? state.selectedPath;
    final host = customHost ??
        (path == ConnectionPathType.tailscale
            ? (_tailscaleHostController.text.trim().isNotEmpty
                ? _tailscaleHostController.text.trim()
                : (state.tailscaleHost ?? state.savedPairedDevice?.tailscaleAddress ?? ''))
            : _hostController.text.trim());
    final port = customPort ?? int.tryParse(_portController.text.trim()) ?? 4371;

    final controller = ref.read(connectionControllerProvider.notifier);
    final success = await controller.connect(
      customHost: host,
      customPort: port,
      specificPath: path,
    );

    if (!mounted) return;

    if (success) {
      final client = ref.read(webSocketClientProvider);
      // ONLY navigate to MainNavigationShell if client is strictly authenticated and paired!
      if (client.currentState.isPaired) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MainNavigationShell(host: host, port: port),
          ),
        );
      } else {
        if (prefillPairingCode != null && prefillPairingCode.isNotEmpty) {
          ref.read(pairingControllerProvider.notifier).setCode(prefillPairingCode);
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PairingScreen(
              host: host,
              port: port,
              initialCode: prefillPairingCode,
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleQrScan() async {
    final qr = await QrScannerSheet.show(context);
    if (qr == null || !mounted) return;

    _hostController.text = qr.host;
    if (qr.tailscaleHost != null) {
      _tailscaleHostController.text = qr.tailscaleHost!;
      ref.read(connectionControllerProvider.notifier).updateTailscaleHost(qr.tailscaleHost!);
    }
    _portController.text = qr.port.toString();
    ref.read(connectionControllerProvider.notifier).updateHost(qr.host);
    ref.read(connectionControllerProvider.notifier).updatePort(qr.port);

    final controller = ref.read(connectionControllerProvider.notifier);
    final paired = await controller.pairWithQr(qr);
    if (!mounted) return;
    if (paired) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainNavigationShell(host: qr.host, port: qr.port),
        ),
      );
    }
  }

  Future<void> _checkTailscaleAgain() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Checking Tailscale status with PC...'),
          ],
        ),
        duration: Duration(seconds: 1),
        backgroundColor: Color(0xFF1E1E1E),
      ),
    );

    final ok = await ref.read(connectionControllerProvider.notifier).refreshDeviceInfo(showLoading: true);
    if (!mounted) return;

    final state = ref.read(connectionControllerProvider);
    final tsAddress = state.tailscaleHost ?? state.savedPairedDevice?.tailscaleAddress;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok && tsAddress != null && tsAddress.isNotEmpty
              ? 'Tailscale Ready: $tsAddress'
              : (ok ? 'Checked: Tailscale not configured on PC' : 'Could not reach PC to query Tailscale'),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: ok && tsAddress != null ? const Color(0xFF1B382B) : const Color(0xFF1E1E1E),
      ),
    );
  }

  void _showTailscaleSetupSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C0C0C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'GLOBAL ACCESS SETUP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: OrbitColors.orbitTextMuted,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: OrbitColors.orbitTextSecondary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Connect to your PC from anywhere',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: OrbitColors.orbitTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Orbit uses Tailscale to create a private peer-to-peer connection between your devices. You don't need to expose Orbit to the public internet or configure router port forwarding.",
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: OrbitColors.orbitTextSecondary,
                  ),
                ),
                const SizedBox(height: 16),

                // Visual 3-step flow diagram
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: OrbitColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildFlowDiagramNode(Icons.computer, 'PC', 'Orbit Daemon'),
                      const Icon(Icons.arrow_forward, size: 14, color: OrbitColors.orbitTextMuted),
                      _buildFlowDiagramNode(Icons.shield_outlined, 'Tailscale', 'Encrypted Mesh'),
                      const Icon(Icons.arrow_forward, size: 14, color: OrbitColors.orbitTextMuted),
                      _buildFlowDiagramNode(Icons.phone_android, 'Phone', 'Orbit Mobile'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Step list
                _buildGuideStep('1', 'Install Tailscale on phone & PC', 'Download the app on both devices from tailscale.com.'),
                _buildGuideStep('2', 'Sign in on both devices', 'Log into the same Tailnet account (Google, GitHub, etc.).'),
                _buildGuideStep('3', 'Orbit detects automatically', 'Orbit reads your peer IP (100.x.y.z) without manual typing.'),
                _buildGuideStep('4', 'Connect securely', 'Establish an end-to-end encrypted direct connection.'),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OrbitButton(
                        label: 'Copy Download Link',
                        onPressed: () async {
                          await Clipboard.setData(const ClipboardData(text: 'https://tailscale.com/download'));
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Tailscale download link copied to clipboard: https://tailscale.com/download'),
                                duration: Duration(seconds: 2),
                                backgroundColor: Color(0xFF1E1E1E),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: OrbitColors.orbitTextPrimary,
                        side: const BorderSide(color: OrbitColors.borderSubtle),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFlowDiagramNode(IconData icon, String title, String subtitle) {
    return Column(
      children: [
        Icon(icon, size: 18, color: OrbitColors.orbitAccent),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: OrbitColors.orbitTextPrimary),
        ),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 9, color: OrbitColors.orbitTextMuted),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(connectionControllerProvider);

    // Sync controllers if state changes from storage
    if (_hostController.text != state.host) {
      _hostController.text = state.host;
    }
    final effectiveTs = state.tailscaleHost ?? state.savedPairedDevice?.tailscaleAddress;
    if (effectiveTs != null && _tailscaleHostController.text != effectiveTs) {
      _tailscaleHostController.text = effectiveTs;
    }
    if (_portController.text != state.port.toString()) {
      _portController.text = state.port.toString();
    }

    final currentTailscale = (state.tailscaleHost != null && state.tailscaleHost!.isNotEmpty)
        ? state.tailscaleHost
        : state.savedPairedDevice?.tailscaleAddress;
    final isTailscaleConfigured = currentTailscale != null && currentTailscale.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // Brand Icon & Title
              const Center(
                child: OrbitLogoWidget(size: 80),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'ORBIT',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    color: OrbitColors.orbitTextPrimary,
                  ),
                ),
              ),
              const Center(
                child: Text(
                  'Remote Development Daemon',
                  style: TextStyle(
                    fontSize: 13,
                    color: OrbitColors.orbitTextSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 36),

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
                const SizedBox(height: 20),
              ],

              // QR Scan Card
              OrbitCard(
                borderColor: OrbitColors.orbitAccent.withOpacity(0.5),
                onTap: _handleQrScan,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: OrbitColors.orbitAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.qr_code_scanner, color: OrbitColors.orbitAccent, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scan Pairing QR Code',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: OrbitColors.orbitTextPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Scan QR on Orbit Desktop for instant pairing',
                            style: TextStyle(fontSize: 11, color: OrbitColors.orbitTextSecondary),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: OrbitColors.orbitAccent, size: 20),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Divider / OR
              const Row(
                children: [
                  Expanded(child: Divider(color: OrbitColors.borderSubtle)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR ENTER MANUALLY',
                      style: TextStyle(
                        color: OrbitColors.orbitTextMuted,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: OrbitColors.borderSubtle)),
                ],
              ),

              const SizedBox(height: 20),

              // Connection Form Card
              OrbitCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connect to PC',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: OrbitColors.orbitTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Connect via local network or remote Tailscale mesh',
                      style: TextStyle(
                        fontSize: 12,
                        color: OrbitColors.orbitTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Connection Path Selector
                    const Text(
                      'Connection:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: OrbitColors.orbitTextSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPathSelectorRow(state, isTailscaleConfigured, currentTailscale),
                    const SizedBox(height: 18),

                    // Dynamic view depending on selected path
                    if (state.selectedPath == ConnectionPathType.localLan) ...[
                      OrbitTextField(
                        controller: _hostController,
                        label: 'Local PC Address',
                        hint: '192.168.1.100 or 127.0.0.1',
                        keyboardType: TextInputType.text,
                        isMonospace: true,
                        prefixIcon: const Icon(Icons.computer,
                            size: 18, color: OrbitColors.orbitTextSecondary),
                        onChanged: (val) =>
                            ref.read(connectionControllerProvider.notifier).updateHost(val),
                      ),
                      const SizedBox(height: 16),
                      OrbitTextField(
                        controller: _portController,
                        label: 'Port',
                        hint: '4371',
                        keyboardType: TextInputType.number,
                        isMonospace: true,
                        prefixIcon: const Icon(Icons.numbers,
                            size: 18, color: OrbitColors.orbitTextSecondary),
                        onChanged: (val) {
                          final p = int.tryParse(val);
                          if (p != null) {
                            ref.read(connectionControllerProvider.notifier).updatePort(p);
                          }
                        },
                      ),
                      const SizedBox(height: 24),
                      OrbitButton(
                        label: state.isConnecting ? 'Connecting...' : 'Connect',
                        isLoading: state.isConnecting,
                        onPressed: state.isConnecting ? null : () => _handleConnect(),
                        width: double.infinity,
                      ),
                    ] else ...[
                      if (currentTailscale != null && currentTailscale.isNotEmpty)
                        _buildTailscaleReadyView(state, currentTailscale)
                      else
                        _buildTailscaleNotConfiguredView(state),
                    ],
                  ],
                ),
              ),

              // Recent Devices Section
              if (state.savedPairedDevice != null) ...[
                const SizedBox(height: 28),
                const Text(
                  'RECENT DEVICES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: OrbitColors.orbitTextTertiary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildRecentDeviceCard(state),
              ],

              // How does this work? Section
              const SizedBox(height: 24),
              _buildHowItWorksSection(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPathSelectorRow(
    ConnectionScreenState state,
    bool isTailscaleConfigured,
    String? currentTailscale,
  ) {
    final lanAddress = state.savedPairedDevice?.pcAddress ??
        (state.host.isNotEmpty ? state.host : '127.0.0.1');

    return Row(
      children: [
        Expanded(
          child: _buildPathSelector(
            label: 'Local Network',
            statusText: 'Available',
            isStatusActive: true,
            addressText: lanAddress,
            isSelected: state.selectedPath == ConnectionPathType.localLan,
            onTap: () {
              ref.read(connectionControllerProvider.notifier).selectPath(ConnectionPathType.localLan);
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildPathSelector(
            label: 'Tailscale',
            statusText: isTailscaleConfigured ? 'Available' : 'Not configured',
            isStatusActive: isTailscaleConfigured,
            addressText: isTailscaleConfigured ? currentTailscale! : 'Remote access',
            isSelected: state.selectedPath == ConnectionPathType.tailscale,
            onTap: () {
              ref.read(connectionControllerProvider.notifier).selectPath(ConnectionPathType.tailscale);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPathSelector({
    required String label,
    required String statusText,
    required bool isStatusActive,
    String? addressText,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF161616) : const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.white.withOpacity(0.4) : OrbitColors.borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.white : OrbitColors.orbitTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isStatusActive ? OrbitColors.orbitSuccess : OrbitColors.orbitTextMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isStatusActive ? OrbitColors.orbitSuccess : OrbitColors.orbitTextMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (addressText != null && addressText.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                addressText,
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: OrbitColors.orbitTextTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTailscaleReadyView(ConnectionScreenState state, String tailscaleAddress) {
    final pcName = state.savedPairedDevice?.pcDisplayName ?? 'Orbit Workstation';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'TAILSCALE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: OrbitColors.orbitTextMuted,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: OrbitColors.orbitSuccess.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OrbitColors.orbitSuccess.withOpacity(0.35)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('● ', style: TextStyle(color: OrbitColors.orbitSuccess, fontSize: 10)),
                  Text(
                    'Ready',
                    style: TextStyle(
                      color: OrbitColors.orbitSuccess,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          pcName,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: OrbitColors.orbitTextPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: OrbitColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tailscale Address',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: OrbitColors.orbitTextSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tailscaleAddress,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Icon(Icons.check_circle_outline, size: 14, color: OrbitColors.orbitSuccess),
            SizedBox(width: 6),
            Text(
              'Tailscale connection available',
              style: TextStyle(fontSize: 12, color: OrbitColors.orbitTextSecondary),
            ),
          ],
        ),
        const SizedBox(height: 18),
        OrbitButton(
          label: state.isConnecting ? 'Connecting...' : 'Connect',
          isLoading: state.isConnecting,
          onPressed: state.isConnecting
              ? null
              : () => _handleConnect(
                    customHost: tailscaleAddress,
                    specificPath: ConnectionPathType.tailscale,
                  ),
          width: double.infinity,
        ),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: () => setState(() => _showManualOverride = !_showManualOverride),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _showManualOverride ? 'Hide manual override' : 'Manual address override',
                  style: const TextStyle(
                    fontSize: 11,
                    color: OrbitColors.orbitTextTertiary,
                    decoration: TextDecoration.underline,
                  ),
                ),
                Icon(
                  _showManualOverride ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 14,
                  color: OrbitColors.orbitTextTertiary,
                ),
              ],
            ),
          ),
        ),
        if (_showManualOverride) ...[
          const SizedBox(height: 12),
          OrbitTextField(
            controller: _tailscaleHostController,
            label: 'Custom Tailscale Host',
            hint: '100.x.y.z',
            keyboardType: TextInputType.text,
            isMonospace: true,
            prefixIcon: const Icon(Icons.public, size: 18, color: OrbitColors.orbitAccent),
            onChanged: (val) =>
                ref.read(connectionControllerProvider.notifier).updateTailscaleHost(val),
          ),
          const SizedBox(height: 10),
          OrbitTextField(
            controller: _portController,
            label: 'Port',
            hint: '4371',
            keyboardType: TextInputType.number,
            isMonospace: true,
            prefixIcon: const Icon(Icons.numbers, size: 18, color: OrbitColors.orbitTextSecondary),
            onChanged: (val) {
              final p = int.tryParse(val);
              if (p != null) {
                ref.read(connectionControllerProvider.notifier).updatePort(p);
              }
            },
          ),
        ],
      ],
    );
  }

  Widget _buildTailscaleNotConfiguredView(ConnectionScreenState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'TAILSCALE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: OrbitColors.orbitTextMuted,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OrbitColors.borderSubtle),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('○ ', style: TextStyle(color: OrbitColors.orbitTextMuted, fontSize: 10)),
                  Text(
                    'Not configured',
                    style: TextStyle(
                      color: OrbitColors.orbitTextSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Secure remote connection',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: OrbitColors.orbitTextPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Orbit uses Tailscale to connect to your PC even when you're away from your local network.\n\nYou'll need Tailscale installed and signed in on both your phone and your PC.",
          style: TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: OrbitColors.orbitTextSecondary,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OrbitButton(
                label: 'Set Up Tailscale',
                onPressed: () => _showTailscaleSetupSheet(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: OrbitColors.orbitTextPrimary,
                  side: const BorderSide(color: OrbitColors.borderSubtle),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _checkTailscaleAgain,
                child: const Text(
                  'Check Again',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: GestureDetector(
            onTap: () => setState(() => _showManualUnconfigured = !_showManualUnconfigured),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _showManualUnconfigured ? 'Hide manual address' : 'Enter manual address instead',
                  style: const TextStyle(
                    fontSize: 11,
                    color: OrbitColors.orbitTextTertiary,
                    decoration: TextDecoration.underline,
                  ),
                ),
                Icon(
                  _showManualUnconfigured ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 14,
                  color: OrbitColors.orbitTextTertiary,
                ),
              ],
            ),
          ),
        ),
        if (_showManualUnconfigured) ...[
          const SizedBox(height: 14),
          OrbitTextField(
            controller: _tailscaleHostController,
            label: 'Tailscale Address',
            hint: '100.x.y.z or workstation.tailnet.ts.net',
            keyboardType: TextInputType.text,
            isMonospace: true,
            prefixIcon: const Icon(Icons.public, size: 18, color: OrbitColors.orbitAccent),
            onChanged: (val) =>
                ref.read(connectionControllerProvider.notifier).updateTailscaleHost(val),
          ),
          const SizedBox(height: 10),
          OrbitTextField(
            controller: _portController,
            label: 'Port',
            hint: '4371',
            keyboardType: TextInputType.number,
            isMonospace: true,
            prefixIcon: const Icon(Icons.numbers, size: 18, color: OrbitColors.orbitTextSecondary),
            onChanged: (val) {
              final p = int.tryParse(val);
              if (p != null) {
                ref.read(connectionControllerProvider.notifier).updatePort(p);
              }
            },
          ),
          const SizedBox(height: 14),
          OrbitButton(
            label: state.isConnecting ? 'Connecting...' : 'Connect',
            isLoading: state.isConnecting,
            onPressed: state.isConnecting
                ? null
                : () => _handleConnect(
                      customHost: _tailscaleHostController.text.trim(),
                      specificPath: ConnectionPathType.tailscale,
                    ),
            width: double.infinity,
          ),
        ],
      ],
    );
  }

  Widget _buildRecentDeviceCard(ConnectionScreenState state) {
    final device = state.savedPairedDevice!;
    final hasTs = device.tailscaleAddress != null && device.tailscaleAddress!.isNotEmpty;

    return OrbitCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: OrbitColors.orbitSurfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.laptop, color: OrbitColors.orbitAccent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.pcDisplayName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: OrbitColors.orbitTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (hasTs)
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: OrbitColors.orbitSuccess,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Tailscale Ready',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: OrbitColors.orbitSuccess,
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: OrbitColors.orbitTextMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Local Network Only',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: OrbitColors.orbitTextMuted,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const StatusPill(label: 'Paired', type: StatusType.online),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: OrbitColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LAN: ${device.pcAddress}:${device.pcPort}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: OrbitColors.orbitTextSecondary,
                  ),
                ),
                if (hasTs) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Tailscale: ${device.tailscaleAddress}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: OrbitColors.orbitAccentCyan,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: OrbitColors.borderSubtle, height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: OrbitColors.borderSubtle),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.wifi, size: 14, color: OrbitColors.orbitTextSecondary),
                  label: const Text('Local LAN', style: TextStyle(fontSize: 12)),
                  onPressed: state.isConnecting
                      ? null
                      : () => _handleConnect(
                            customHost: device.pcAddress,
                            customPort: device.pcPort,
                            specificPath: ConnectionPathType.localLan,
                          ),
                ),
              ),
              if (hasTs) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: OrbitColors.borderSubtle),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.public, size: 14, color: OrbitColors.orbitAccent),
                    label: const Text('Tailscale', style: TextStyle(fontSize: 12)),
                    onPressed: state.isConnecting
                        ? null
                        : () => _handleConnect(
                              customHost: device.tailscaleAddress,
                              customPort: device.pcPort,
                              specificPath: ConnectionPathType.tailscale,
                            ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksSection() {
    return OrbitCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _howItWorksExpanded = !_howItWorksExpanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.help_outline, size: 16, color: OrbitColors.orbitTextSecondary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'How does this work?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: OrbitColors.orbitTextPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    _howItWorksExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: OrbitColors.orbitTextTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_howItWorksExpanded) ...[
            const SizedBox(height: 12),
            const Divider(color: OrbitColors.borderSubtle, height: 1),
            const SizedBox(height: 12),
            _buildGuideStep('1', 'Install Tailscale on your phone', 'Download from the App Store or Google Play Store.'),
            _buildGuideStep('2', 'Sign in', 'Log in with your Google, GitHub, or Microsoft account.'),
            _buildGuideStep('3', 'Install/sign in on your PC', 'Enable Global Access in Orbit Desktop on your workstation.'),
            _buildGuideStep('4', 'Same Tailnet', 'Ensure both phone and PC are connected to the same Tailnet.'),
            _buildGuideStep('5', 'Return to Orbit', 'Orbit detects the secure 100.x.y.z endpoint automatically.'),
            _buildGuideStep('6', 'Connect', 'Establish encrypted peer-to-peer access without router port forwarding.'),
          ],
        ],
      ),
    );
  }

  Widget _buildGuideStep(String stepNumber, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: OrbitColors.orbitSurfaceElevated,
              shape: BoxShape.circle,
              border: Border.all(color: OrbitColors.borderSubtle),
            ),
            alignment: Alignment.center,
            child: Text(
              stepNumber,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: OrbitColors.orbitAccent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: OrbitColors.orbitTextPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: OrbitColors.orbitTextSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
