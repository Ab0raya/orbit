import 'package:flutter/material.dart';
import 'package:orbit_mobile/shared/theme/orbit_colors.dart';

class FilePathBar extends StatelessWidget {
  final String currentPath;
  final VoidCallback onNavigateUp;
  final VoidCallback onRefresh;
  final VoidCallback onCreateFolder;
  final VoidCallback? onCopyPath;
  final VoidCallback? onGoHome;
  final VoidCallback? onOpenTerminal;

  const FilePathBar({
    super.key,
    required this.currentPath,
    required this.onNavigateUp,
    required this.onRefresh,
    required this.onCreateFolder,
    this.onCopyPath,
    this.onGoHome,
    this.onOpenTerminal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: OrbitColors.orbitBackground,
        border: Border(
          bottom: BorderSide(color: OrbitColors.orbitBorder),
        ),
      ),
      child: Row(
        children: [
          // Navigate Up / Back button in rounded square
          Tooltip(
            message: 'Navigate back to parent directory',
            child: InkWell(
              onTap: onNavigateUp,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: OrbitColors.orbitCard,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: OrbitColors.orbitBorder),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  size: 17,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (onGoHome != null) ...[
            const SizedBox(width: 6),
            // Home / Browse Roots button in rounded square
            Tooltip(
              message: 'Go to root directory',
              child: InkWell(
                onTap: onGoHome,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: OrbitColors.orbitCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: OrbitColors.orbitBorder),
                  ),
                  child: const Icon(
                    Icons.home_outlined,
                    size: 17,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          // Path display
          Expanded(
            child: InkWell(
              onTap: onCopyPath,
              borderRadius: BorderRadius.circular(4),
              child: Tooltip(
                message: 'Tap to copy directory path',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Text(
                      currentPath.isEmpty ? 'LOCATIONS' : currentPath,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Action Buttons
          if (onOpenTerminal != null && currentPath.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.terminal_rounded, size: 18),
              color: OrbitColors.orbitAccentCyan,
              tooltip: 'Open Directory in Terminal',
              onPressed: onOpenTerminal,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
          if (onCopyPath != null) ...[
            IconButton(
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              color: Colors.white70,
              tooltip: 'Copy Directory Path',
              onPressed: onCopyPath,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: Colors.white70,
            tooltip: 'Refresh',
            onPressed: onRefresh,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}
