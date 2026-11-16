import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../app/app_theme.dart';
import '../../core/ui/surfaces.dart';
import 'local_endpoint.dart';

Future<PairingHint?> scanPairingHint(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<PairingHint>(builder: (_) => const _ScanPairingHint()),
    );

Future<void> showPairingQr(BuildContext context, PairingHint hint) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ESP IoT pairing QR'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 240),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Semantics(
                image: true,
                label: 'Pairing QR code',
                child: PrettyQrView.data(
                  data: hint.encode(),
                  decoration: const PrettyQrDecoration(
                    quietZone: PrettyQrQuietZone.standard,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SelectableText(hint.endpoint.origin),
            const SizedBox(height: 6),
            const Text(
              'Scan on another phone using the same Wi-Fi. The code contains the address and device ID.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );

class _ScanPairingHint extends StatefulWidget {
  const _ScanPairingHint();

  @override
  State<_ScanPairingHint> createState() => _ScanPairingHintState();
}

class _ScanPairingHintState extends State<_ScanPairingHint> {
  bool _cameraOpened = false;
  bool _returning = false;
  bool _invalid = false;

  void _detect(BarcodeCapture capture) {
    if (!mounted || _returning) return;
    for (final code in capture.barcodes) {
      final payload = code.rawValue;
      if (code.format != BarcodeFormat.qrCode || payload == null) continue;
      try {
        final hint = PairingHint.decode(payload);
        _returning = true;
        Navigator.pop(context, hint);
        return;
      } on FormatException {
        if (!_invalid) setState(() => _invalid = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pairing QR')),
      body: SafeArea(
        child: _cameraOpened
            ? MobileScanner(
                onDetect: _detect,
                placeholderBuilder: (_) => Center(
                  child: Semantics(
                    liveRegion: true,
                    child: const Text('Opening camera…'),
                  ),
                ),
                overlayBuilder: (context, constraints) => Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * .4,
                    ),
                    child: ColoredBox(
                      color: AppColors.surface,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _invalid
                                ? 'That code could not be read as an ESP IoT v1 hint. Try another pairing QR.'
                                : 'Point the camera at an ESP IoT pairing QR code.',
                            style: TextStyle(
                              color: _invalid
                                  ? AppColors.violet
                                  : AppColors.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                errorBuilder: (context, error) => ScreenScroll(
                  children: [
                    EmptyPanel(
                      icon: Icons.no_photography_outlined,
                      title: 'Camera unavailable',
                      description:
                          error.errorCode ==
                              MobileScannerErrorCode.permissionDenied
                          ? 'Allow camera access in Android Settings, or go back and enter the address manually.'
                          : 'The camera could not start. Go back and enter the address manually.',
                      action: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back to Discover'),
                      ),
                    ),
                  ],
                ),
              )
            : ScreenScroll(
                children: [
                  EmptyPanel(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Scan with your camera',
                    description:
                        'ESP IoT uses the camera to read the device address and identity from a pairing QR code. '
                        'Android may ask for camera access. You can also enter the address manually from Discover.',
                    action: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => setState(() => _cameraOpened = true),
                          child: const Text('Open camera'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Back to Discover'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
