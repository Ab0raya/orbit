import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/ai_permission_controller.dart';
import '../models/ai_permission_models.dart';
import '../../../shared/theme/orbit_colors.dart';

class PermissionApprovalCard extends ConsumerWidget {
  final AiPermissionRequest request;

  const PermissionApprovalCard({
    super.key,
    required this.request,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHigh = request.isHighRisk;
    final borderColor = isHigh
        ? OrbitColors.orbitError
        : request.risk == AiPermissionRisk.medium
            ? const Color(0xFFF59E0B)
            : OrbitColors.orbitBorderLight;

    final bannerBg = isHigh
        ? OrbitColors.orbitError.withValues(alpha: 0.12)
        : const Color(0xFF161616);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bannerBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: borderColor.withValues(alpha: 0.3))),
            ),
            child: Row(
              children: [
                Icon(
                  isHigh ? Icons.gpp_bad_rounded : Icons.shield_outlined,
                  size: 18,
                  color: borderColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ORBIT AI',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: OrbitColors.orbitTextMuted,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        'Permission Required',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isHigh ? OrbitColors.orbitError : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // Risk Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isHigh
                        ? OrbitColors.orbitError.withValues(alpha: 0.2)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isHigh
                          ? OrbitColors.orbitError.withValues(alpha: 0.6)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.6),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    isHigh ? 'HIGH RISK' : request.risk.name.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: isHigh ? OrbitColors.orbitError : const Color(0xFFFCD34D),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main Card Body
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Orbit AI wants to run with ${request.tool.toUpperCase()}:',
                  style: const TextStyle(
                    fontSize: 12,
                    color: OrbitColors.orbitTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),

                // Target code box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF050505),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: OrbitColors.orbitBorder),
                  ),
                  child: SelectableText(
                    request.tool == 'bash' ? '\$ ${request.target}' : request.target,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Scope / Directory
                if (request.projectPath.isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Project: ',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: OrbitColors.orbitTextMuted,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          request.projectPath,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Action explanation
                Text(
                  isHigh
                      ? 'CAUTION: This is a potentially destructive action. It requires your explicit confirmation.'
                      : 'This action will execute a command on your computer.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isHigh ? const Color(0xFFFCA5A5) : OrbitColors.orbitTextMuted,
                  ),
                ),
                const SizedBox(height: 14),

                // Action Buttons: [ Deny ] [ Allow ] and optionally [ Always Allow ]
                Row(
                  children: [
                    // Deny button
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isHigh ? OrbitColors.orbitError : Colors.white70,
                          side: BorderSide(
                            color: isHigh ? OrbitColors.orbitError : OrbitColors.orbitBorder,
                            width: 1,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text(
                          'Deny',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () {
                          ref
                              .read(aiPermissionControllerProvider.notifier)
                              .resolvePermission(request.permissionId, 'reject');
                        },
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Allow button (once)
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text(
                          'Allow',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () {
                          ref
                              .read(aiPermissionControllerProvider.notifier)
                              .resolvePermission(request.permissionId, 'once');
                        },
                      ),
                    ),
                  ],
                ),

                // If non-destructive, provide an Always Allow option safely
                if (!isHigh) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: OrbitColors.orbitTextMuted,
                      ),
                      onPressed: () {
                        ref
                            .read(aiPermissionControllerProvider.notifier)
                            .resolvePermission(request.permissionId, 'always');
                      },
                      child: const Text(
                        'Always Allow for this session',
                        style: TextStyle(fontSize: 11, decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
