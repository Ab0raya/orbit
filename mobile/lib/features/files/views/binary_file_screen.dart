import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:orbit_mobile/core/providers.dart';
import 'package:orbit_mobile/protocol/models/file_models.dart';
import 'package:orbit_mobile/shared/theme/orbit_colors.dart';
import 'package:orbit_mobile/shared/widgets/orbit_card.dart';
import 'package:orbit_mobile/protocol/models/ai_context.dart';
import 'package:orbit_mobile/features/ai/controllers/ai_task_controller.dart';
import 'package:orbit_mobile/features/ai/views/ai_command_center_screen.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';

class BinaryFileScreen extends ConsumerStatefulWidget {
  final String path;
  final String fileName;

  const BinaryFileScreen({
    super.key,
    required this.path,
    required this.fileName,
  });

  @override
  ConsumerState<BinaryFileScreen> createState() => _BinaryFileScreenState();
}

class _BinaryFileScreenState extends ConsumerState<BinaryFileScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  BinaryReadResponse? _binaryData;
  Uint8List? _previewBytes;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = ref.read(webSocketClientProvider);
      final res = await client.sendRequest(
        'files.read_binary',
        payload: {'path': widget.path},
      );

      if (!mounted) return;

      if (res.success && res.payload != null) {
        final binaryRes = BinaryReadResponse.fromJson(res.payload!);
        Uint8List? bytes;
        if (binaryRes.content != null && binaryRes.content!.isNotEmpty) {
          bytes = base64Decode(binaryRes.content!);
        }

        setState(() {
          _isLoading = false;
          _binaryData = binaryRes;
          _previewBytes = bytes;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = res.error?.message ?? 'Failed to read binary metadata';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  String _formatHexDump(Uint8List bytes) {
    final buffer = StringBuffer();
    const bytesPerLine = 16;
    final maxBytes = bytes.length > 256 ? 256 : bytes.length;

    for (var i = 0; i < maxBytes; i += bytesPerLine) {
      // Offset
      buffer.write(i.toRadixString(16).padLeft(4, '0').toUpperCase());
      buffer.write(': ');

      // Hex bytes
      final end = (i + bytesPerLine < maxBytes) ? i + bytesPerLine : maxBytes;
      for (var j = i; j < end; j++) {
        buffer.write(bytes[j].toRadixString(16).padLeft(2, '0').toUpperCase());
        buffer.write(' ');
      }

      // Padding if last line is short
      if (end - i < bytesPerLine) {
        buffer.write('   ' * (bytesPerLine - (end - i)));
      }

      buffer.write(' │ ');

      // ASCII representation
      for (var j = i; j < end; j++) {
        final b = bytes[j];
        if (b >= 32 && b <= 126) {
          buffer.write(String.fromCharCode(b));
        } else {
          buffer.write('.');
        }
      }

      buffer.writeln();
    }

    if (bytes.length > maxBytes) {
      buffer.writeln('... (${bytes.length - maxBytes} more bytes not shown)');
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OrbitColors.orbitBackground,
      appBar: AppBar(
        backgroundColor: OrbitColors.orbitSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: OrbitColors.orbitTextPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileName,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: OrbitColors.orbitTextPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const Text(
              'BINARY FILE',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: OrbitColors.orbitTextMuted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: OrbitColors.orbitAccent, size: 20),
            tooltip: 'Ask Orbit AI',
            onPressed: () {
              final sep = widget.path.contains('\\') ? '\\' : '/';
              final lastSep = widget.path.lastIndexOf(sep);
              final parentDir = lastSep > 0 ? widget.path.substring(0, lastSep) : widget.path;
              final aiContext = AiContext.fromDirectory(parentDir);
              ref.read(aiTaskControllerProvider.notifier).setContext(aiContext);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AiCommandCenterScreen(
                    initialContext: aiContext,
                    initialPrompt: 'What does this binary file ${widget.fileName} do?',
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: OrbitColors.orbitTextSecondary, size: 20),
            onPressed: _loadMetadata,
            tooltip: 'Reload metadata',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OrbitLoadingIndicator(size: 40),
                  SizedBox(height: 16),
                  Text(
                    'Inspecting binary metadata...',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: OrbitColors.orbitTextMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: OrbitColors.orbitError),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: OrbitColors.orbitError,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: OrbitColors.orbitCard,
                            foregroundColor: OrbitColors.orbitTextPrimary,
                          ),
                          onPressed: _loadMetadata,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Card
                      OrbitCard(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: OrbitColors.orbitSurfaceElevated,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: OrbitColors.orbitBorder),
                              ),
                              child: const Icon(
                                Icons.memory,
                                color: OrbitColors.orbitAccent,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.fileName,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: OrbitColors.orbitTextPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _binaryData?.formattedSize ?? 'Unknown size',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: OrbitColors.orbitAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _binaryData?.mimeType ?? 'application/octet-stream',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: OrbitColors.orbitTextMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Notice Banner
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: OrbitColors.orbitSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OrbitColors.orbitBorder),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, size: 20, color: OrbitColors.orbitTextSecondary),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'This is a binary file and cannot be viewed or edited as plain text.',
                                style: TextStyle(
                                  color: OrbitColors.orbitTextSecondary,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // File Metadata Details
                      const Text(
                        'METADATA',
                        style: TextStyle(
                          color: OrbitColors.orbitTextMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 10),
                      OrbitCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildMetaRow('File Name', widget.fileName),
                            const Divider(color: OrbitColors.orbitBorder, height: 16),
                            _buildMetaRow('Full Path', widget.path),
                            const Divider(color: OrbitColors.orbitBorder, height: 16),
                            _buildMetaRow('Size', _binaryData?.formattedSize ?? '-'),
                            const Divider(color: OrbitColors.orbitBorder, height: 16),
                            _buildMetaRow('MIME Type', _binaryData?.mimeType ?? '-'),
                            if (_binaryData?.modifiedAt != null) ...[
                              const Divider(color: OrbitColors.orbitBorder, height: 16),
                              _buildMetaRow(
                                'Modified',
                                DateFormat('yyyy-MM-dd HH:mm:ss').format(
                                  DateTime.fromMillisecondsSinceEpoch(_binaryData!.modifiedAt!),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Hex Preview (if preview bytes available)
                      if (_previewBytes != null && _previewBytes!.isNotEmpty) ...[
                        Row(
                          children: [
                            const Text(
                              'HEX DUMP PREVIEW',
                              style: TextStyle(
                                color: OrbitColors.orbitTextMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${_previewBytes!.length} bytes',
                              style: const TextStyle(
                                color: OrbitColors.orbitAccent,
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF090A0D),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: OrbitColors.orbitBorder),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SelectableText(
                              _formatHexDump(_previewBytes!),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: OrbitColors.orbitAccent,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              color: OrbitColors.orbitTextMuted,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: OrbitColors.orbitTextPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
