import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../look.dart';
import '../services/lookup.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

/// Opens the camera to scan a book's barcode. Returns the ISBN-13, or null.
Future<String?> scanIsbn() {
  dropFocus();
  return navKey.currentState!.push<String>(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, _, _) => const ScanScreen(),
    transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: c),
  ));
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with SingleTickerProviderStateMixin {
  final _ctl = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.code128],
    detectionSpeed: DetectionSpeed.normal,
  );
  late final AnimationController _line = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat(reverse: true);
  bool _done = false, _torch = false, _typing = false;
  String _hint = 'Point at the barcode on the back of the book';

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    Look.overlay();
    _line.dispose();
    _ctl.dispose();
    super.dispose();
  }

  void _found(BarcodeCapture cap) {
    if (_done || _typing) return;
    for (final b in cap.barcodes) {
      final isbn = isbnFromBarcode(b.rawValue ?? '');
      if (isbn != null) {
        _done = true;
        Buzz.medium();
        Sfx.play('check');
        Navigator.of(context).pop(isbn);
        return;
      }
    }
    if (cap.barcodes.isNotEmpty && _hint.startsWith('Point')) {
      setState(() => _hint = 'That barcode isn’t an ISBN. Try the one with 978 or 979.');
    }
  }

  Future<void> _type() async {
    final t = TextEditingController();
    var err = '';
    _typing = true; // don't let the camera act while the dialog is open
    await openDialog((ctx) => StatefulBuilder(
          builder: (ctx, set) => AppDialog(title: 'Type the ISBN', children: [
            const Sub('It’s printed above or below the barcode, 10 or 13 digits.'),
            AppInput(t, '978…', maxLength: 17, type: TextInputType.number, autofocus: true),
            ErrText(err),
          ], actions: [
            const Btn('Cancel'),
            Btn('Look up', kind: Kind.pri, onTap: () {
              final isbn = isbnFromBarcode(t.text);
              if (isbn == null) {
                set(() => err = 'That doesn’t look like a valid ISBN.');
                return false;
              }
              return true;
            }, then: () {
              final isbn = isbnFromBarcode(t.text);
              if (isbn != null && mounted) {
                _done = true;
                Navigator.of(context).pop(isbn);
              }
            }),
          ]),
        ));
    _typing = false;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = min(mq.size.width - 64, 320.0), h = w * .56;
    final window = Rect.fromCenter(center: Offset(mq.size.width / 2, mq.size.height * .42), width: w, height: h);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: MobileScanner(
            controller: _ctl,
            onDetect: _found,
            scanWindow: window,
            errorBuilder: (_, e) => Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text(
                  e.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Shelfwise needs the camera to scan barcodes. Allow it in Android settings, or type the ISBN instead.'
                      : 'The camera couldn’t start. You can type the ISBN instead.',
                  textAlign: TextAlign.center,
                  style: nu(15, FontWeight.w700, Colors.white, 1.4),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _line,
              builder: (_, _) => CustomPaint(painter: _Overlay(window, Curves.easeInOut.transform(_line.value))),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: window.bottom + 24,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(_hint, key: ValueKey(_hint), textAlign: TextAlign.center, style: nu(15, FontWeight.w700, Colors.white, 1.4)),
          ),
        ),
        Positioned(
          top: mq.padding.top + 10,
          left: 12,
          right: 12,
          child: Row(children: [
            _round(Icons.arrow_back_rounded, 'Close scanner', () => Navigator.of(context).pop()),
            const SizedBox(width: 12),
            Expanded(child: Text('Scan a book', style: nu(18, FontWeight.w800, Colors.white))),
            _round(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded, 'Torch', () {
              _ctl.toggleTorch();
              setState(() => _torch = !_torch);
            }),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: mq.padding.bottom + 30,
          child: Center(
            child: Pill('Type the ISBN instead', kind: Kind.normal, icon: const Icon(Icons.keyboard_rounded, size: 18), onTap: _type),
          ),
        ),
      ]),
    );
  }

  Widget _round(IconData i, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: Pressable(
          onTap: onTap,
          scale: .88,
          child: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(i, color: Colors.white, size: 22),
          ),
        ),
      );
}

class _Overlay extends CustomPainter {
  final Rect r;
  final double t;
  _Overlay(this.r, this.t);
  @override
  void paint(Canvas c, Size s) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(20));
    c.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & s)
        ..addRRect(rr),
      Paint()..color = const Color(0x99000000),
    );
    final corner = Paint()
      ..color = C.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const k = 28.0;
    for (final (x, y, dx, dy) in [(r.left, r.top, 1.0, 1.0), (r.right, r.top, -1.0, 1.0), (r.left, r.bottom, 1.0, -1.0), (r.right, r.bottom, -1.0, -1.0)]) {
      c.drawPath(
        Path()
          ..moveTo(x, y + dy * k)
          ..lineTo(x, y + dy * 10)
          ..quadraticBezierTo(x, y, x + dx * 10, y)
          ..lineTo(x + dx * k, y),
        corner,
      );
    }
    final y = r.top + 14 + (r.height - 28) * t;
    c.drawLine(
      Offset(r.left + 18, y),
      Offset(r.right - 18, y),
      Paint()
        ..shader = LinearGradient(colors: [C.orange.withValues(alpha: 0), C.orange, C.orange.withValues(alpha: 0)])
            .createShader(Rect.fromLTWH(r.left, y - 2, r.width, 4))
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_Overlay o) => o.t != t || o.r != r;
}
