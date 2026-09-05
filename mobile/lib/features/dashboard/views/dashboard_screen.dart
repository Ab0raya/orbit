import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_logo_widget.dart';
import '../controllers/dashboard_controller.dart';
import '../../connection/views/connection_screen.dart';
import '../../pairing/views/pairing_screen.dart';
import '../../scripts/views/scripts_screen.dart';
import '../../../core/networking/connection_state.dart';
import '../../../core/networking/connection_manager.dart';
import '../../../core/providers.dart';

class DashboardScreen extends ConsumerWidget {
  final String host;
  final int port;
  final VoidCallback? onNavigateToAi;
  final VoidCallback? onNavigateToFiles;
  final VoidCallback? onNavigateToTerminal;
  final VoidCallback? onNavigateToProjects;

  const DashboardScreen({
    super.key,
    required this.host,
    required this.port,
    this.onNavigateToAi,
    this.onNavigateToFiles,
    this.onNavigateToTerminal,
    this.onNavigateToProjects,
  });

  static Widget _buildTailscaleStatusBadge(TailscaleEnvironmentStatus status) {
    final Color color;
    final String symbol;
    switch (status) {
      case TailscaleEnvironmentStatus.ready:
        color = OrbitColors.orbitSuccess;
        symbol = '✓';
        break;
      case TailscaleEnvironmentStatus.setupRequired:
        color = OrbitColors.orbitWarning;
        symbol = '⚠';
        break;
      case TailscaleEnvironmentStatus.unavailable:
        color = OrbitColors.orbitTextMuted;
        symbol = '✕';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            symbol,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showPcDetails(BuildContext context, dynamic sysInfo) {
    if (sysInfo == null) return;

    final isTailscale = host.startsWith('100.') ||
        (sysInfo.tailscale?.ip != null && host == sysInfo.tailscale!.ip);

    TailscaleEnvironmentStatus tsStatus = TailscaleEnvironmentStatus.unavailable;
    if (sysInfo.tailscale != null) {
      final ts = sysInfo.tailscale!;
      if (ts.isReady) {
        tsStatus = TailscaleEnvironmentStatus.ready;
      } else if (ts.isSetupRequired) {
        tsStatus = TailscaleEnvironmentStatus.setupRequired;
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0C0C0C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Workstation Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: OrbitColors.orbitTextPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: OrbitColors.orbitTextMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(color: OrbitColors.orbitBorder),
                const SizedBox(height: 10),
                _buildDetailRow('Hostname', sysInfo.hostname),
                _buildDetailRow('Operating System', '${sysInfo.os} ${sysInfo.osVersion}'),
                _buildDetailRow('Architecture', sysInfo.architecture, isMono: true),
                _buildDetailRow('Connection', isTailscale ? '● Tailscale' : '● Local Network'),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tailscale Environment',
                        style: TextStyle(color: OrbitColors.orbitTextSecondary, fontSize: 13),
                      ),
                      _buildTailscaleStatusBadge(tsStatus),
                    ],
                  ),
                ),
                if (sysInfo.tailscale?.ip != null)
                  _buildDetailRow('Tailscale IP', sysInfo.tailscale!.ip!, isMono: true),
                if (sysInfo.primaryIp != null)
                  _buildDetailRow('Local LAN IP', sysInfo.primaryIp!, isMono: true),
                const SizedBox(height: 14),
                const Text(
                  'Network Interfaces',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: OrbitColors.orbitTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                ...sysInfo.network.map<Widget>((net) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            net.interfaceName,
                            style: const TextStyle(
                              color: OrbitColors.orbitTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            net.ip,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildDetailRow(String label, String value, {bool isMono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: OrbitColors.orbitTextSecondary, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              color: OrbitColors.orbitTextPrimary,
              fontFamily: isMono ? 'monospace' : null,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardControllerProvider);
    final sysInfo = state.systemInfo;
    final agent = state.agentStatus;
    final connState = ref.watch(connectionStateProvider).value ??
        ref.watch(webSocketClientProvider).currentState;

    final String hostTitle;
    final bool isPaired = connState.isPaired;

    if (isPaired) {
      hostTitle = sysInfo?.hostname ?? (state.isLoading ? 'Loading...' : 'Aburaya');
    } else if (connState.status == OrbitConnectionStatus.connectedUnpaired) {
      hostTitle = 'Unpaired Device';
    } else if (connState.status == OrbitConnectionStatus.reconnecting) {
      hostTitle = 'Reconnecting...';
    } else {
      hostTitle = 'Disconnected';
    }

    final uptimeStr = agent != null ? agent.formattedUptime : '00:01:58';
    final osName = sysInfo != null ? sysInfo.os : 'Omarchy';
    final archName = sysInfo != null ? sysInfo.architecture : 'x86_64';

    final isTailscale = host.startsWith('100.') ||
        (sysInfo?.tailscale?.ip != null && host == sysInfo!.tailscale!.ip);

    return Scaffold(
      backgroundColor: OrbitColors.orbitBackground,
      body: SafeArea(
        child: RefreshIndicator(
          color: Colors.white,
          backgroundColor: const Color(0xFF141414),
          onRefresh: () => ref.read(dashboardControllerProvider.notifier).refreshAll(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top App Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Brand Left
                    const Row(
                      children: [
                        OrbitLogoWidget(size: 26),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ORBIT',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Remote Development Companion',
                              style: TextStyle(
                                fontSize: 9.5,
                                color: OrbitColors.orbitTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Connected Status Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F0F),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: OrbitColors.orbitBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isPaired ? OrbitColors.orbitSuccess : OrbitColors.orbitWarning,
                              shape: BoxShape.circle,
                              boxShadow: isPaired
                                  ? [
                                      BoxShadow(
                                        color: OrbitColors.orbitSuccess.withValues(alpha: 0.6),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isPaired ? (isTailscale ? 'Connected • TS' : 'Connected • LAN') : 'Unpaired',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // Hero Editorial Headline
                const Text(
                  'Your\nDev Environment,\nEverywhere.',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1.15,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Run. Build. Ship. From Anywhere.',
                  style: TextStyle(
                    fontSize: 13,
                    color: OrbitColors.orbitTextMuted,
                  ),
                ),

                const SizedBox(height: 24),

                // Workstation Card
                InkWell(
                  onTap: () => _showPcDetails(context, sysInfo),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: OrbitColors.orbitCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: OrbitColors.orbitBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: OrbitColors.orbitBorderSubtle),
                          ),
                          child: const Icon(
                            Icons.laptop_chromebook_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hostTitle,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$host:$port',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontFamily: 'monospace',
                                  color: OrbitColors.orbitTextMuted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF121212),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: OrbitColors.orbitBorderSubtle),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: BoxDecoration(
                                            color: isPaired ? OrbitColors.orbitSuccess : OrbitColors.orbitWarning,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          isPaired ? 'Paired / Connected' : 'Unpaired',
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            color: OrbitColors.orbitTextSecondary,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF121212),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: OrbitColors.orbitBorderSubtle),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: BoxDecoration(
                                            color: isTailscale ? OrbitColors.orbitAccent : Colors.white60,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          isTailscale ? 'Tailscale' : 'Local LAN',
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            color: OrbitColors.orbitTextSecondary,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: OrbitColors.orbitTextMuted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),

                if (!isPaired) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161208),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF854D0E)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_outlined, color: OrbitColors.orbitWarning, size: 18),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Pairing Required to access files and AI.',
                            style: TextStyle(color: OrbitColors.orbitWarning, fontSize: 11),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PairingScreen(host: host, port: port),
                              ),
                            );
                          },
                          child: const Text('Pair Now', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // 2 System Metric Tiles
                Row(
                  children: [
                    // Agent Uptime
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: OrbitColors.orbitCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OrbitColors.orbitBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.access_time_rounded, size: 14, color: OrbitColors.orbitTextMuted),
                                SizedBox(width: 6),
                                Text(
                                  'Agent Uptime',
                                  style: TextStyle(fontSize: 11, color: OrbitColors.orbitTextMuted),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              uptimeStr,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Orbit v0.1.0',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: OrbitColors.orbitTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // System
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: OrbitColors.orbitCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OrbitColors.orbitBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.computer_rounded, size: 14, color: OrbitColors.orbitTextMuted),
                                SizedBox(width: 6),
                                Text(
                                  'System',
                                  style: TextStyle(fontSize: 11, color: OrbitColors.orbitTextMuted),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              osName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              archName,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: OrbitColors.orbitTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 26),

                // WORKSTATION TOOLS Header
                const Text(
                  'WORKSTATION TOOLS',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: OrbitColors.orbitTextMuted,
                  ),
                ),

                const SizedBox(height: 12),

                // 4 Tool Cards
                _buildToolCard(
                  icon: Icons.auto_awesome,
                  title: 'AI Command Center',
                  subtitle: 'Workstation AI assistant, code inspection, plan & build',
                  onTap: onNavigateToAi,
                ),
                const SizedBox(height: 10),

                _buildToolCard(
                  icon: Icons.code_rounded,
                  title: 'Projects & Git',
                  subtitle: 'Discover workspaces, Git status, branch & commits',
                  onTap: onNavigateToProjects,
                ),
                const SizedBox(height: 10),

                _buildToolCard(
                  icon: Icons.terminal_rounded,
                  title: 'Remote Terminal',
                  subtitle: 'Interactive PTY shell with real-time streaming',
                  onTap: onNavigateToTerminal,
                ),
                const SizedBox(height: 10),

                _buildToolCard(
                  icon: Icons.folder_outlined,
                  title: 'File Explorer',
                  subtitle: 'Browse directories, read & edit files remotely',
                  onTap: onNavigateToFiles,
                ),
                const SizedBox(height: 10),

                _buildToolCard(
                  icon: Icons.play_circle_outline_rounded,
                  title: 'Saved Scripts',
                  subtitle: 'Save and execute custom terminal scripts on demand',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ScriptsScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 18),

                // Disconnect option at bottom
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.power_settings_new, size: 14, color: OrbitColors.orbitTextMuted),
                    label: const Text('Disconnect from Workstation', style: TextStyle(color: OrbitColors.orbitTextMuted, fontSize: 11)),
                    onPressed: () {
                      ref.read(webSocketClientProvider).disconnect();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const ConnectionScreen()),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolCard({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: OrbitColors.orbitCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OrbitColors.orbitBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF131313),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: OrbitColors.orbitBorderSubtle),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: OrbitColors.orbitTextMuted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: OrbitColors.orbitTextMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
