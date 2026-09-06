import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:orbit_mobile/protocol/models/file_models.dart';
import 'package:orbit_mobile/shared/theme/orbit_colors.dart';

class FileEntryTile extends StatelessWidget {
  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onCopyPath;
  final VoidCallback? onOpenTerminal;

  const FileEntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.onCopyPath,
    this.onOpenTerminal,
  });

  String get _formattedDate {
    if (entry.modifiedAt == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(entry.modifiedAt! * 1000);
    return DateFormat('MMM d, HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDir = entry.isDirectory;

    return InkWell(
      onTap: onTap,
      onLongPress: onCopyPath,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0x14FFFFFF), width: 0.6),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isDir ? Icons.folder_rounded : Icons.description_outlined,
              size: 20,
              color: isDir ? const Color(0xFFD4D4D8) : const Color(0xFFA1A1AA),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: isDir ? FontWeight.w600 : FontWeight.normal,
                      color: entry.hidden
                          ? OrbitColors.orbitTextMuted
                          : Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formattedDate.isNotEmpty
                        ? _formattedDate
                        : entry.formattedSize,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: OrbitColors.orbitTextMuted,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert,
                size: 18,
                color: OrbitColors.orbitTextMuted,
              ),
              color: const Color(0xFF141414),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: OrbitColors.orbitBorder),
              ),
              padding: EdgeInsets.zero,
              onSelected: (action) {
                if (action == 'copy_path') {
                  onCopyPath?.call();
                } else if (action == 'open_terminal') {
                  onOpenTerminal?.call();
                } else if (action == 'rename') {
                  onRename();
                } else if (action == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (context) => [
                if (isDir && onOpenTerminal != null)
                  const PopupMenuItem(
                    value: 'open_terminal',
                    child: Row(
                      children: [
                        Icon(Icons.terminal_rounded, size: 16, color: OrbitColors.orbitAccentCyan),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Open in Terminal',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'copy_path',
                  child: Row(
                    children: [
                      const Icon(Icons.copy_rounded, size: 16, color: Colors.white70),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isDir ? 'Copy Directory Path' : 'Copy Path',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 16, color: Colors.white70),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Rename',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 16, color: OrbitColors.orbitError),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Delete',
                          style: TextStyle(color: OrbitColors.orbitError, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
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
    );
  }
}
