import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/app_feel.dart';
import '../services/civic_sync.dart';
import '../theme/app_theme.dart';

/// Camera scanner shared by friend sync and device transfer. [parse] turns a
/// raw barcode into the value the caller wants back, or null to keep looking.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({
    super.key,
    this.title = 'Scan a code',
    this.hint =
        'Point the camera at their Voteaxis QR. '
        'We only read the 6-character sync code.',
    this.parse,
  });

  final String title;
  final String hint;
  final String? Function(String raw)? parse;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _done = false;

  String? _parse(String raw) {
    final parse = widget.parse;
    if (parse != null) return parse(raw);
    return parseFriendSyncCode(raw, requireUri: true);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done || !mounted) return;
    for (final barcode in capture.barcodes) {
      final value = _parse(barcode.rawValue ?? '');
      if (value == null) continue;
      _done = true;
      AppFeel.medium();
      if (!mounted) return;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.sheet,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Expanded(
            child: ClipRect(child: MobileScanner(onDetect: _onDetect)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Text(
              widget.hint,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: AppColors.sheet.withValues(alpha: 0.72),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
