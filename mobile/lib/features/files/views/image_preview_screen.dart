import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orbit_mobile/core/providers.dart';
import 'package:orbit_mobile/protocol/models/file_models.dart';
import 'package:orbit_mobile/shared/theme/orbit_colors.dart';
import 'package:orbit_mobile/protocol/models/ai_context.dart';
import 'package:orbit_mobile/features/ai/controllers/ai_task_controller.dart';
import 'package:orbit_mobile/features/ai/views/ai_command_center_screen.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';

class ImagePreviewScreen extends ConsumerStatefulWidget {
  final String path;
  final String fileName;

  const ImagePreviewScreen({
    super.key,
    required this.path,
    required this.fileName,
  });

  @override
  ConsumerState<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends ConsumerState<ImagePreviewScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  BinaryReadResponse? _binaryData;
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
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
          _imageBytes = bytes;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = res.error?.message ?? 'Failed to load image';
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

  bool get _isSvg {
    final ext = widget.fileName.split('.').last.toLowerCase();
    return ext == 'svg' || _binaryData?.mimeType == 'image/svg+xml';
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
            if (_binaryData != null)
              Text(
                '${_binaryData!.formattedSize}${_binaryData!.dimensionsText.isNotEmpty ? " • ${_binaryData!.dimensionsText}" : ""}',
                style: const TextStyle(
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
                    initialPrompt: 'What does this image asset ${widget.fileName} contain?',
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: OrbitColors.orbitTextSecondary, size: 20),
            onPressed: _loadImage,
            tooltip: 'Reload image',
          ),
        ],
      ),
      body: Column(
        children: [
          // Main Preview Canvas
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OrbitLoadingIndicator(size: 40),
                        SizedBox(height: 16),
                        Text(
                          'Loading image preview...',
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
                              const Icon(Icons.broken_image_outlined,
                                  size: 48, color: OrbitColors.orbitError),
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
                                onPressed: _loadImage,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _binaryData?.isTooLarge == true
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      size: 48, color: Colors.amberAccent),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Image File Too Large',
                                    style: TextStyle(
                                      color: OrbitColors.orbitTextPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'File size is ${_binaryData?.formattedSize ?? "oversized"}, exceeding the preview limit.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: OrbitColors.orbitTextMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _imageBytes == null
                            ? const Center(
                                child: Text(
                                  'No image data available',
                                  style: TextStyle(color: OrbitColors.orbitTextMuted),
                                ),
                              )
                            : Container(
                                color: const Color(0xFF0D0F12),
                                width: double.infinity,
                                height: double.infinity,
                                child: InteractiveViewer(
                                  minScale: 0.5,
                                  maxScale: 5.0,
                                  child: Center(
                                    child: _isSvg
                                        ? SvgPicture.memory(
                                            _imageBytes!,
                                            fit: BoxFit.contain,
                                            placeholderBuilder: (_) => const Center(
                                              child: OrbitLoadingIndicator(size: 40),
                                            ),
                                          )
                                        : Image.memory(
                                            _imageBytes!,
                                            fit: BoxFit.contain,
                                            errorBuilder: (context, error, stackTrace) =>
                                                const Center(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.broken_image,
                                                      color: OrbitColors.orbitError, size: 40),
                                                  SizedBox(height: 8),
                                                  Text(
                                                    'Failed to render image format',
                                                    style: TextStyle(
                                                        color: OrbitColors.orbitError,
                                                        fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
          ),

          // Metadata Footer Card
          if (_binaryData != null) _buildMetadataFooter(),
        ],
      ),
    );
  }

  Widget _buildMetadataFooter() {
    final data = _binaryData!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: OrbitColors.orbitSurface,
        border: Border(top: BorderSide(color: OrbitColors.orbitBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Format badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: OrbitColors.orbitAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: OrbitColors.orbitAccent.withValues(alpha: 0.4)),
              ),
              child: Text(
                data.extension.toUpperCase().isEmpty
                    ? 'IMAGE'
                    : data.extension.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: OrbitColors.orbitAccent,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Dimensions and Size
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (data.dimensionsText.isNotEmpty) ...[
                        Text(
                          data.dimensionsText,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: OrbitColors.orbitTextPrimary,
                          ),
                        ),
                        const Text(
                          ' • ',
                          style: TextStyle(color: OrbitColors.orbitTextMuted),
                        ),
                      ],
                      Text(
                        data.formattedSize,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: OrbitColors.orbitTextSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.mimeType,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: OrbitColors.orbitTextMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Zoom hint
            const Icon(Icons.zoom_in, color: OrbitColors.orbitTextMuted, size: 18),
            const SizedBox(width: 4),
            const Text(
              'Pinch to zoom',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: OrbitColors.orbitTextMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
