import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../art.dart';
import '../theme.dart';

/// Shows the animated splash over [child] for a moment on launch, then fades it away.
/// The app builds underneath meanwhile, so the splash hides start-up work instead of adding to it.
class SplashGate extends StatefulWidget {
  final Widget child;
  const SplashGate({super.key, required this.child});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2100))..forward();
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _gone = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _skip() {
    if (_c.value < .78) _c.animateTo(1, duration: const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (!_gone)
        Positioned.fill(
          child: GestureDetector(
            onTap: _skip,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) {
                final out = Curves.easeIn.transform(((_c.value - .82) / .18).clamp(0.0, 1.0));
                return Opacity(
                  opacity: 1 - out,
                  child: Transform.scale(scale: 1 + out * .06, child: _Splash(t: _c.value * 2100)),
                );
              },
            ),
          ),
        ),
    ]);
  }
}

class _Splash extends StatelessWidget {
  final double t; // milliseconds since start
  const _Splash({required this.t});

  double _p(double start, double dur, [Curve c = Curves.easeOut]) => c.transform(((t - start) / dur).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    const books = [
      (Color(0xFF1E1A14), 1.0),
      (Color(0xFFD9C493), .86),
      (Color(0xFFF26B2A), .95),
      (Color(0xFF8F9F80), .8),
      (Color(0xFF1B2A44), .92),
    ];
    final owl = _p(80, 520, springCurve);
    final word = _p(900, 450);
    final tag = _p(1150, 420);
    final line = _p(1300, 500, Curves.easeInOut);
    return Material(
      color: C.cream,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // the owl lands on the shelf
          Transform.translate(
            offset: Offset(0, (1 - owl) * -30 + sin(t / 260) * 2.5 * owl),
            child: Transform.scale(scale: .5 + .5 * owl, child: Opacity(opacity: owl.clamp(0, 1), child: SvgPicture.string(owlSvg, width: 118, height: 107))),
          ),
          const SizedBox(height: 6),
          // books drop onto the plank one by one
          SizedBox(
            width: 210,
            height: 74,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
              for (final (i, (c, h)) in books.indexed)
                Builder(builder: (_) {
                  final v = _p(320 + i * 110, 420, Curves.bounceOut);
                  return Positioned(
                    left: 22 + i * 34.0,
                    bottom: 10,
                    child: Opacity(
                      opacity: _p(320 + i * 110, 120),
                      child: Transform.translate(
                        offset: Offset(0, (1 - v) * -70),
                        child: Transform.rotate(
                          angle: (i == 4 ? -.12 : 0) * v,
                          alignment: Alignment.bottomRight,
                          child: Container(
                            width: 30,
                            height: 60 * h,
                            decoration: BoxDecoration(
                              color: c,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: const [BoxShadow(color: Color(0x40000000), offset: Offset(1, 3), blurRadius: 4)],
                              gradient: LinearGradient(colors: [Color.lerp(c, Colors.black, .25)!, c, c], stops: const [0, .25, 1]),
                            ),
                            child: Align(
                              alignment: const Alignment(0, -.5),
                              child: Container(width: 16, height: 2.5, color: Colors.white.withValues(alpha: .55)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Transform.scale(
                  scaleX: _p(150, 380),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFD2B484), Color(0xFF8F6F43)]),
                      boxShadow: const [BoxShadow(color: Color(0x40000000), offset: Offset(0, 4), blurRadius: 6)],
                    ),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 26),
          Opacity(
            opacity: word,
            child: Transform.translate(
              offset: Offset(0, (1 - word) * 14),
              child: const Text('Shelfwise', style: TextStyle(fontFamily: F.serif, fontWeight: FontWeight.w800, fontSize: 44, color: C.black, letterSpacing: -.5)),
            ),
          ),
          Opacity(
            opacity: tag,
            child: Column(children: [
              const Text('your cozy reading nook', style: TextStyle(fontFamily: F.hand, fontWeight: FontWeight.w500, fontSize: 26, color: C.orange)),
              SizedBox(width: 210, height: 8, child: CustomPaint(painter: _Line(line))),
            ]),
          ),
          SizedBox(height: mq.size.height * .08),
          Opacity(
            opacity: _p(1250, 300),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB8692A).withValues(alpha: .35 + .65 * ((sin(t / 140 - i * 1.1) + 1) / 2)),
                    shape: BoxShape.circle,
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Line extends CustomPainter {
  final double t;
  _Line(this.t);
  @override
  void paint(Canvas c, Size s) {
    if (t <= 0) return;
    final sx = s.width / 200, sy = s.height / 8;
    final p = Path()
      ..moveTo(2 * sx, 6 * sy)
      ..cubicTo(50 * sx, 1 * sy, 120 * sx, 1 * sy, 198 * sx, 4 * sy);
    final m = p.computeMetrics().first;
    c.drawPath(
      m.extractPath(0, m.length * t),
      Paint()
        ..color = C.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Line o) => o.t != t;
}
