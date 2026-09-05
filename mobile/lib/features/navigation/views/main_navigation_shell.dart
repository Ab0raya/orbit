import 'package:flutter/material.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../ai/views/ai_command_center_screen.dart';
import '../../dashboard/views/dashboard_screen.dart';
import '../../files/views/file_explorer_screen.dart';
import '../../projects/views/projects_screen.dart';
import '../../terminal/views/terminal_screen.dart';

class MainNavigationShell extends StatefulWidget {
  final String host;
  final int port;
  final int initialIndex;

  const MainNavigationShell({
    super.key,
    required this.host,
    required this.port,
    this.initialIndex = 0,
  });

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void switchTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        host: widget.host,
        port: widget.port,
        onNavigateToAi: () => switchTab(1),
        onNavigateToFiles: () => switchTab(2),
        onNavigateToTerminal: () => switchTab(3),
        onNavigateToProjects: () => switchTab(4),
      ),
      AiCommandCenterScreen(
        onBack: () => switchTab(0),
      ),
      FileExplorerScreen(
        onBack: () => switchTab(0),
      ),
      TerminalScreen(
        onBack: () => switchTab(0),
      ),
      ProjectsScreen(
        onBack: () => switchTab(0),
      ),
    ];

    return Scaffold(
      backgroundColor: OrbitColors.orbitBackground,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: OrbitColors.orbitBackground,
          border: Border(
            top: BorderSide(color: OrbitColors.orbitBorder, width: 0.8),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.grid_view_rounded, 'Home'),
                _buildNavItem(1, Icons.auto_awesome, 'AI'),
                _buildNavItem(2, Icons.folder_outlined, 'Files'),
                _buildNavItem(3, Icons.terminal_rounded, 'Terminal'),
                _buildNavItem(4, Icons.code_rounded, 'Projects'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;

    return InkWell(
      onTap: () => switchTab(index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF141414) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? OrbitColors.orbitBorder : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : OrbitColors.orbitTextMuted,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Colors.white : OrbitColors.orbitTextMuted,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
