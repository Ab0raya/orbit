import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../protocol/models/pairing_models.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_button.dart';

class QrScannerSheet extends StatefulWidget {
  const QrScannerSheet({super.key});

  static Future<OrbitPairingQrPayload?> show(BuildContext context) {
    return showModalBottomSheet<OrbitPairingQrPayload>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const QrScannerSheet(),
    );
  }

  @override
  State<QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<QrScannerSheet> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessing = false;
  bool _torchOn = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    final rawValue = barcode?.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    final parsed = OrbitPairingQrPayload.tryParse(rawValue);
    if (parsed == null) {
      setState(() {
        _errorMessage = 'Invalid QR code. Please scan an Orbit Pairing QR.';
      });
      return;
    }

    if (parsed.isExpired) {
      setState(() {
        _errorMessage = 'Pairing code expired. Please generate a new code on PC.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.85,
      decoration: const BoxDecoration(
        color: OrbitColors.orbitBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: OrbitColors.orbitBorder),
          left: BorderSide(color: OrbitColors.orbitBorder),
          right: BorderSide(color: OrbitColors.orbitBorder),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: OrbitColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.qr_code_scanner, color: OrbitColors.orbitAccent, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'SCAN PAIRING QR CODE',
                  style: TextStyle(
                    color: OrbitColors.orbitTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _torchOn ? Icons.flash_on : Icons.flash_off,
                    color: _torchOn ? OrbitColors.orbitAccent : OrbitColors.orbitTextMuted,
                    size: 20,
                  ),
                  onPressed: () async {
                    await _controller.toggleTorch();
                    setState(() => _torchOn = !_torchOn);
                  },
                  tooltip: 'Toggle Flashlight',
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: OrbitColors.orbitTextMuted, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          const Divider(color: OrbitColors.borderSubtle, height: 1),

          // Scanner viewport
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),

                // Cyberpunk reticle frame
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _errorMessage != null
                          ? OrbitColors.orbitError
                          : OrbitColors.orbitAccent.withOpacity(0.8),
                      width: 2,
                    ),
                  ),
                ),

                // Reticle corner accents
                SizedBox(
                  width: 268,
                  height: 268,
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: OrbitColors.orbitAccent, width: 4),
                              left: BorderSide(color: OrbitColors.orbitAccent, width: 4),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: OrbitColors.orbitAccent, width: 4),
                              right: BorderSide(color: OrbitColors.orbitAccent, width: 4),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: OrbitColors.orbitAccent, width: 4),
                              left: BorderSide(color: OrbitColors.orbitAccent, width: 4),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: OrbitColors.orbitAccent, width: 4),
                              right: BorderSide(color: OrbitColors.orbitAccent, width: 4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Error message toast overlay
                if (_errorMessage != null)
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: OrbitColors.orbitError.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom instructions
          Container(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
            color: OrbitColors.orbitSurface,
            child: Column(
              children: [
                const Text(
                  'Point your camera at the QR code displayed on Orbit Desktop.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: OrbitColors.orbitTextSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                OrbitButton(
                  text: 'Cancel',
                  variant: OrbitButtonVariant.outline,
                  width: double.infinity,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
