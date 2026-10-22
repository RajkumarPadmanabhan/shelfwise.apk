import 'dart:math';

import 'package:flutter/material.dart';

import '../services/sfx.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'common.dart';

final _rnd = Random();
double _r() => _rnd.nextDouble();

/// One keyframe: offset 0..1, translate, rotation (deg), opacity, scale.
class KF {
  final double o, x, y, r, a, sx, sy;
  const KF(this.o, {this.x = 0, this.y = 0, this.r = 0, this.a = 1, this.sx = 1, this.sy = 1});
}

KF lerpKF(List<KF> k, double t) {
  if (t <= k.first.o) return k.first;
  for (var i = 1; i < k.length; i++) {
    final a = k[i - 1], b = k[i];
    if (t <= b.o) {
      final u = (t - a.o) / (b.o - a.o);
      double l(double p, double q) => p + (q - p) * u;
      return KF(t, x: l(a.x, b.x), y: l(a.y, b.y), r: l(a.r, b.r), a: l(a.a, b.a), sx: l(a.sx, b.sx), sy: l(a.sy, b.sy));
    }
  }
  return k.last;
}

Matrix4 kfMatrix(KF f, Offset origin) => Matrix4.identity()
  ..translateByDouble(origin.dx + f.x, origin.dy + f.y, 0, 1)
  ..rotateZ(f.r * pi / 180)
  ..scaleByDouble(f.sx, f.sy, 1, 1)
  ..translateByDouble(-origin.dx, -origin.dy, 0, 1);

// ---------------------------------------------------------------------------
// Tear / smash
// ---------------------------------------------------------------------------

/// A cover you can tear (or a decoration you can smash) by sliding across it.
class TearCover extends StatefulWidget {
  final double w, h;
  final Widget face;
  final Widget Function() pieceFace;
  final bool gadget;
  final Color paper;
  final VoidCallback onTorn;
  final VoidCallback? onTap;
  const TearCover(
      {super.key,
      required this.w,
      required this.h,
      required this.face,
      required this.pieceFace,
      required this.onTorn,
      this.gadget = false,
      this.paper = const Color(0xFFF6EFE2),
      this.onTap});

  @override
  State<TearCover> createState() => TearCoverState();
}

class TearCoverState extends State<TearCover> {
  final _key = GlobalKey();
  final List<Offset> _pts = [];
  Offset _start = Offset.zero;
  double _mv = 0, _dx = 0;
  bool _done = false, _torn = false;

  void tear() {
    if (_torn) return;
    _torn = true;
    _done = true;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    Sfx.play('tear');
    Buzz.rip();
    final screenH = MediaQuery.sizeOf(context).height;
    Fx.add(_TearBurst(rect: rect, face: widget.pieceFace, gadget: widget.gadget, paper: widget.paper, screenH: screenH), 2600);
    setState(() {
      _pts.clear();
      _dx = 0;
    });
    Future.delayed(const Duration(milliseconds: 1250), () {
      if (mounted) widget.onTorn();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rot = _dx / widget.w * 7 * pi / 180;
    return Visibility(
      visible: !_torn,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onPanStart: (d) {
          if (_done) return;
          _start = d.localPosition;
          _mv = 0;
          _pts
            ..clear()
            ..add(d.localPosition);
        },
        onPanUpdate: (d) {
          if (_done) return;
          final delta = d.localPosition - _start;
          _mv = max(_mv, delta.distance);
          if ((d.localPosition - _pts.last).distance > 6) _pts.add(d.localPosition);
          setState(() => _dx = delta.dx);
          if (delta.distance >= widget.w * .7) tear();
        },
        onPanEnd: (_) {
          if (_done) return;
          final tap = _mv < 10;
          setState(() {
            _pts.clear();
            _dx = 0;
          });
          if (tap) widget.onTap?.call();
        },
        child: AnimatedContainer(
          duration: _pts.isEmpty ? const Duration(milliseconds: 250) : Duration.zero,
          curve: springCurve,
          transform: Matrix4.identity()
            ..translateByDouble(_dx * .06, 0, 0, 1)
            ..rotateZ(rot),
          transformAlignment: Alignment.center,
          child: SizedBox(
            key: _key,
            width: widget.w,
            height: widget.h,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: widget.face),
              if (_pts.length > 1) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Crack(List.of(_pts))))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Crack extends CustomPainter {
  final List<Offset> pts;
  _Crack(this.pts);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (final (i, p) in pts.indexed) {
      final q = p + Offset(0, i.isOdd ? 3.5 : -3.5);
      i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
    }
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.miter;
    canvas.drawPath(path, base..color = const Color.fromRGBO(0, 0, 0, .55)..strokeWidth = 5);
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.miter
      ..color = Colors.white
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_Crack o) => true;
}

class _Piece {
  final List<Offset> poly;
  final Offset c;
  final List<KF> k;
  final int dur, delay;
  _Piece(this.poly, this.c, this.k, this.dur, this.delay);
}

class _Scrap {
  final Offset at;
  final Size size;
  final Color color;
  final int shape;
  final List<KF> k;
  final int dur, delay;
  _Scrap(this.at, this.size, this.color, this.shape, this.k, this.dur, this.delay);
}

class _TearBurst extends StatefulWidget {
  final Rect rect;
  final Widget Function() face;
  final bool gadget;
  final Color paper;
  final double screenH;
  const _TearBurst({required this.rect, required this.face, required this.gadget, required this.paper, required this.screenH});
  @override
  State<_TearBurst> createState() => _TearBurstState();
}

class _TearBurstState extends State<_TearBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..forward();
  final pieces = <_Piece>[];
  final scraps = <_Scrap>[];
  static const _pieceEase = Cubic(.4, .05, .8, .5);
  static const _scrapEase = Cubic(.2, .6, .4, 1);

  @override
  void initState() {
    super.initState();
    final w = widget.rect.width, h = widget.rect.height;
    const cols = 3, rows = 4;
    final p = List.generate(rows + 1, (j) => List.generate(cols + 1, (i) {
          var x = i / cols * w, y = j / rows * h;
          if (i > 0 && i < cols) x += (_r() - .5) * w / cols * .6;
          if (j > 0 && j < rows) y += (_r() - .5) * h / rows * .6;
          return Offset(x, y);
        }));
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final poly = [p[j][i], p[j][i + 1], p[j + 1][i + 1], p[j + 1][i]];
        final c = poly.reduce((a, b) => a + b) / 4;
        final ox = (c.dx - w / 2) * 1.2, oy = (c.dy - h / 2) * .5;
        final rot = (_r() - .5) * 160, fall = widget.screenH * .65 + _r() * 90, drift = (_r() - .5) * 60;
        pieces.add(_Piece(
            poly,
            c,
            [
              const KF(0),
              KF(.16, x: ox * .4, y: oy * .3 - 6, r: rot * .25),
              KF(.85, x: ox * 1.3 + drift, y: fall, r: rot, a: .9),
              KF(1, x: ox * 1.4 + drift, y: fall + 30, r: rot * 1.1, a: 0),
            ],
            1400 + (_r() * 500).round(),
            (_r() * 140).round()));
      }
    }
    final pal = [const Color(0xFFFFFDF6), const Color(0xFFF3E6CC), const Color(0xFFFFF8EC), widget.paper];
    for (var q = 0; q < (widget.gadget ? 14 : 32); q++) {
      final ang = _r() * pi * 2, dist = 80 + _r() * 150;
      final dx = cos(ang) * dist, dy = sin(ang) * dist * .7 - 50;
      final fall = widget.screenH * .5 + _r() * 120, rot = (_r() - .5) * 760, sway = (_r() - .5) * 90;
      scraps.add(_Scrap(
        Offset(w * .15 + _r() * w * .7, h * .15 + _r() * h * .7),
        Size(7 + _r() * 13, 6 + _r() * 11),
        pal[q % pal.length],
        q % 3,
        [
          const KF(0),
          KF(.28, x: dx, y: dy, r: rot * .4),
          KF(.65, x: dx + sway, y: dy + fall * .5, r: rot * .7),
          KF(1, x: dx - sway * .6, y: dy + fall, r: rot, a: 0),
        ],
        1400 + (_r() * 800).round(),
        (_r() * 120).round(),
      ));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _t(int delay, int dur, Curve e) {
    final ms = _c.value * 2500 - delay;
    return e.transform((ms / dur).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rect;
    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(clipBehavior: Clip.none, children: [
          for (final pc in pieces)
            Builder(builder: (_) {
              final f = lerpKF(pc.k, _t(pc.delay, pc.dur, _pieceEase));
              return Positioned.fill(
                child: Opacity(
                  opacity: f.a.clamp(0, 1),
                  child: Transform(
                    transform: kfMatrix(f, pc.c),
                    child: ClipPath(clipper: _PolyClip(pc.poly), child: widget.face()),
                  ),
                ),
              );
            }),
          for (final s in scraps)
            Builder(builder: (_) {
              final f = lerpKF(s.k, _t(s.delay, s.dur, _scrapEase));
              return Positioned(
                left: s.at.dx,
                top: s.at.dy,
                width: s.size.width,
                height: s.size.height,
                child: Opacity(
                  opacity: f.a.clamp(0, 1),
                  child: Transform(
                    transform: kfMatrix(f, Offset(s.size.width / 2, s.size.height / 2)),
                    child: ClipPath(clipper: _Jag(s.shape), child: ColoredBox(color: s.color)),
                  ),
                ),
              );
            }),
        ]),
      ),
    );
  }
}

class _PolyClip extends CustomClipper<Path> {
  final List<Offset> poly;
  _PolyClip(this.poly);
  @override
  Path getClip(Size size) => Path()..addPolygon(poly, true);
  @override
  bool shouldReclip(_) => false;
}

class _Jag extends CustomClipper<Path> {
  final int shape;
  _Jag(this.shape);
  static const _s = [
    [0.0, .12, .34, 0, 1, .22, .86, 1, .40, .88, .08, 1],
    [.10, 0, 1, .14, .92, .70, .60, 1, 0, .80],
    [0.0, 0, .70, .08, 1, .60, .55, 1, .12, .74],
  ];
  @override
  Path getClip(Size size) {
    final v = _s[shape];
    return Path()
      ..addPolygon([for (var i = 0; i < v.length; i += 2) Offset(v[i] * size.width, v[i + 1] * size.height)], true);
  }

  @override
  bool shouldReclip(_) => false;
}

/// The "you tore it" message that pops in after a tear.
class TornMessage extends StatelessWidget {
  final String emoji, title, body;
  const TornMessage({super.key, required this.emoji, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: springCurve,
      builder: (_, t, c) => Opacity(opacity: t.clamp(0, 1), child: Transform.scale(scale: .7 + .3 * t, child: c)),
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 44)),
          const SizedBox(height: 6),
          Text(title, textAlign: TextAlign.center, style: nu(20, FontWeight.w800)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: nu(14, FontWeight.w600, C.muted, 1.4)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Decorations you can play with
// ---------------------------------------------------------------------------

class _Anim {
  final Alignment origin;
  final int ms;
  final List<KF> k;
  const _Anim(this.origin, this.ms, this.k);
}

List<KF> _rot(List<double> d) => [for (final (i, v) in d.indexed) KF(i / (d.length - 1), r: v)];

final _anims = <String, _Anim>{
  'sway': _Anim(Alignment.bottomCenter, 900, _rot([0, -7, 6, -4, 0])),
  'swing': _Anim(Alignment.topCenter, 1100, _rot([0, -12, 10, -6, 3, 0])),
  'wob': _Anim(Alignment.bottomCenter, 700, _rot([0, -6, 6, -4, 0])),
  'ring': _Anim(Alignment.bottomCenter, 800, _rot([0, -9, 9, -9, 9, -6, 6, 0])),
  'flip': _Anim(Alignment.center, 900, _rot([0, 180])),
  'bounce': const _Anim(Alignment.bottomCenter, 700, [
    KF(0),
    KF(.25, y: -22, sx: .96, sy: 1.05),
    KF(.5, sx: 1.08, sy: .9),
    KF(.75, y: -8),
    KF(1),
  ]),
  'spin': const _Anim(Alignment.bottomCenter, 1000, [KF(0), KF(.25, sx: -1), KF(.5), KF(.75, sx: -1), KF(1)]),
  'squeak': const _Anim(Alignment.bottomCenter, 450, [KF(0), KF(1 / 3, sx: 1.18, sy: .78), KF(2 / 3, sx: .94, sy: 1.1), KF(1)]),
};

const decorAnim = {
  'pot': 'sway', 'cactus': 'sway', 'succ': 'sway', 'vase': 'sway', 'frame': 'swing', 'pens': 'wob', 'scope': 'swing',
  'teddy': 'bounce', 'globe': 'spin', 'clock': 'ring', 'hour': 'flip', 'duck': 'squeak', 'trophy': 'bounce', 'cup': 'bounce',
  'cd': 'spin',
};

const decorHint = {
  'lamp': 'Tap to switch the light on or off.',
  'candle': 'Tap to light it or blow it out.',
  'cam': 'Tap to take a photo.',
  'owl': 'Tap it and see what happens.',
  'cd': 'Tap to spin the disc. 🎵',
};

/// A big decoration that reacts when tapped; slide across it to smash it.
class DecorStage extends StatefulWidget {
  final String kind;
  final bool lit;
  final ValueChanged<bool> onLit;
  final VoidCallback? onSmashed;
  final double size;
  const DecorStage({super.key, required this.kind, required this.lit, required this.onLit, this.onSmashed, this.size = 140});

  @override
  State<DecorStage> createState() => DecorStageState();
}

class DecorStageState extends State<DecorStage> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  final _tear = GlobalKey<TearCoverState>();
  _Anim? _cur;
  late bool _lit = widget.lit;
  final _bits = <Widget>[];
  bool _gone = false;

  void smash() => _tear.currentState?.tear();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _float(String text, double l, double t, [int delay = 0]) {
    final k = UniqueKey();
    Future.delayed(Duration(milliseconds: delay), () {
      if (!mounted) return;
      setState(() => _bits.add(_FloatText(key: k, text: text, l: l, t: t)));
      Future.delayed(const Duration(milliseconds: 1150), () {
        if (mounted) setState(() => _bits.removeWhere((w) => w.key == k));
      });
    });
  }

  void _addBit(Widget w, int ms) {
    final k = UniqueKey();
    final keyed = KeyedSubtree(key: k, child: w);
    setState(() => _bits.add(keyed));
    Future.delayed(Duration(milliseconds: ms), () {
      if (mounted) setState(() => _bits.removeWhere((x) => x.key == k));
    });
  }

  void _run(_Anim a) {
    _cur = a;
    _c.duration = Duration(milliseconds: a.ms);
    _c.forward(from: 0);
  }

  void play() {
    if (_gone) return;
    final k = widget.kind;
    Buzz.light();
    if (k == 'lamp' || k == 'candle') {
      final on = !_lit;
      Sfx.play(k == 'lamp' ? (on ? 'lampon' : 'lampoff') : (on ? 'candleon' : 'blow'));
      setState(() => _lit = on);
      widget.onLit(on);
      _run(const _Anim(Alignment.center, 260, [KF(0), KF(.5, sx: 1.07, sy: 1.07), KF(1)]));
      _float(on ? (k == 'lamp' ? '💡 on' : '🔥 lit') : (k == 'lamp' ? 'off' : 'blown out'), 50, 12);
      return;
    }
    Sfx.play(Sfx.decor[k] ?? 'bounce');
    if (k == 'owl') {
      _flyAway();
      return;
    }
    if (k == 'cam') {
      Fx.add(const _Flash(), 450);
      _run(const _Anim(Alignment.bottomCenter, 300, [KF(0), KF(.2, sx: .92, sy: .9), KF(1)]));
      _float('📸 click!', 50, 8);
      _addBit(const _Polaroid(), 2000);
      return;
    }
    _run(_anims[decorAnim[k] ?? 'bounce']!);
    if (k == 'cup') {
      for (var i = 0; i < 4; i++) {
        _addBit(_Puff(delay: i * 180), 2000);
      }
    }
    if (k == 'clock') _float('⏰ ring!', 50, 10);
    if (k == 'duck') _float('squeak!', 50, 10);
    if (k == 'teddy') _float('💕', 50, 10);
    if (k == 'cd') _float('🎵 spin!', 50, 10);
    if (k == 'trophy') {
      for (final (i, p) in const [(28.0, 24.0), (72.0, 20.0), (40.0, 8.0), (62.0, 40.0)].indexed) {
        _float('✨', p.$1, p.$2, i * 140);
      }
    }
  }

  void _flyAway() {
    _run(const _Anim(Alignment.center, 1700, [
      KF(0),
      KF(.1, x: 6, y: -16, sx: .8, r: -6),
      KF(.22, x: 18, y: -38, r: 5),
      KF(.36, x: 40, y: -74, sx: .78, r: -8),
      KF(.52, x: 86, y: -124, sx: .85, sy: .85, r: 6),
      KF(.76, x: 160, y: -210, sx: .47, sy: .62, r: -10, a: .85),
      KF(1, x: 280, y: -340, sx: .3, sy: .3, a: 0),
    ]));
    for (var i = 0; i < 8; i++) {
      _addBit(_Feather(color: const [Color(0xFF8A6FB0), Color(0xFFD8C7EE), Colors.white][i % 3]), 2600);
    }
    Future.delayed(const Duration(milliseconds: 2300), () {
      if (!mounted) return;
      Sfx.play('owl');
      _run(const _Anim(Alignment.bottomCenter, 650, [
        KF(0, y: -60, a: 0, sx: .7, sy: .7),
        KF(.6, y: 6, a: 1, sx: 1.05, sy: .95),
        KF(.8, y: -4),
        KF(1),
      ]));
      _float('hoo-hoo!', 50, 6);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final face = AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final a = _cur;
        if (a == null || !_c.isAnimating && _c.value == 1 && a.ms != 1700) return child!;
        final f = lerpKF(a.k, Curves.easeInOut.transform(_c.value));
        final o = Offset(s / 2 + a.origin.x * s / 2, s / 2 + a.origin.y * s / 2);
        return Opacity(opacity: f.a.clamp(0, 1), child: Transform(transform: kfMatrix(f, o), child: child));
      },
      child: GadgetView(widget.kind, w: s, h: s, lit: _lit),
    );
    return SizedBox(
      width: s,
      height: s,
      child: Stack(clipBehavior: Clip.none, children: [
        TearCover(
          key: _tear,
          w: s,
          h: s,
          gadget: true,
          face: face,
          pieceFace: () => GadgetView(widget.kind, w: s, h: s, lit: _lit),
          onTap: play,
          onTorn: () {
            _gone = true;
            widget.onSmashed?.call();
          },
        ),
        ..._bits,
      ]),
    );
  }
}

class _FloatText extends StatelessWidget {
  final String text;
  final double l, t;
  const _FloatText({super.key, required this.text, required this.l, required this.t});
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (_, c) => TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOut,
            builder: (_, v, _) {
              final f = lerpKF(const [KF(0, sx: .6, sy: .6, a: 0), KF(.25, y: -14, sx: 1.1, sy: 1.1), KF(1, y: -46, a: 0)], v);
              return Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  left: c.maxWidth * l / 100 - 60,
                  width: 120,
                  top: c.maxHeight * t / 100 + f.y,
                  child: Opacity(
                    opacity: f.a.clamp(0, 1),
                    child: Transform.scale(
                      scale: f.sx,
                      child: Text(text, textAlign: TextAlign.center, style: nu(14, FontWeight.w800, C.brown)),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

class _Puff extends StatelessWidget {
  final int delay;
  const _Puff({required this.delay});
  @override
  Widget build(BuildContext context) {
    final dx = (_r() - .5) * 28;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (_, c) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 1300 + delay),
          curve: Interval(delay / (1300 + delay), 1, curve: Curves.easeOut),
          builder: (_, v, _) {
            final f = lerpKF([const KF(0, sx: .6, a: 0), KF(.3, x: dx * .5, y: -20, sx: 1.2, a: .8), KF(1, x: dx, y: -68, sx: 2.3, a: 0)], v);
            return Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: c.maxWidth * .52 - 7 + f.x,
                top: c.maxHeight * .3 + f.y,
                child: Opacity(
                  opacity: f.a.clamp(0, 1),
                  child: Transform.scale(
                    scale: f.sx,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.fromRGBO(190, 180, 170, .55),
                        boxShadow: [BoxShadow(color: Color.fromRGBO(190, 180, 170, .55), blurRadius: 6)],
                      ),
                    ),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _Polaroid extends StatelessWidget {
  const _Polaroid();
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (_, c) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1950),
          curve: const Interval(.13, 1, curve: Curves.easeInOut),
          builder: (_, v, _) {
            final f = lerpKF(const [KF(0, y: -10, r: -4, a: 0), KF(.25, r: -4), KF(.7, y: 58, r: 5), KF(1, y: 80, r: 8, a: 0)], v);
            return Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: c.maxWidth / 2 - 26,
                top: c.maxHeight * .62 + f.y,
                child: Opacity(
                  opacity: f.a.clamp(0, 1),
                  child: Transform.rotate(
                    angle: f.r * pi / 180,
                    child: Container(
                      width: 52,
                      height: 62,
                      padding: const EdgeInsets.fromLTRB(5, 5, 5, 15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .3), offset: Offset(0, 3), blurRadius: 8)],
                      ),
                      child: const ColoredBox(color: Color(0xFFD9D4CB)),
                    ),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _Feather extends StatelessWidget {
  final Color color;
  const _Feather({required this.color});
  @override
  Widget build(BuildContext context) {
    final dx = (_r() - .5) * 160, up = -30 - _r() * 50, fall = 80 + _r() * 180, rot1 = _r() * 180, rot2 = _r() * 540;
    final delay = 150 + (_r() * 500).round(), dur = 1600 + (_r() * 600).round();
    final sx = .3 + _r() * .4, sy = .3 + _r() * .4, w = 5 + _r() * 7, h = 9 + _r() * 9;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (_, c) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: dur + delay),
          curve: Interval(delay / (dur + delay), 1, curve: Curves.easeOut),
          builder: (_, v, _) {
            final f = lerpKF([const KF(0), KF(.3, x: dx, y: up, r: rot1), KF(1, x: dx * 1.3, y: fall, r: rot2, a: 0)], v);
            return Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: c.maxWidth * sx + f.x,
                top: c.maxHeight * sy + f.y,
                child: Opacity(
                  opacity: v == 0 ? 0 : f.a.clamp(0, 1),
                  child: Transform.rotate(
                    angle: f.r * pi / 180,
                    child: Container(
                      width: w,
                      height: h,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(9), topRight: Radius.circular(9), bottomRight: Radius.circular(9)),
                      ),
                    ),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _Flash extends StatelessWidget {
  const _Flash();
  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOut,
          builder: (_, v, _) => ColoredBox(color: Colors.white.withValues(alpha: v < .12 ? v / .12 * .85 : (1 - v) / .88 * .85)),
        ),
      );
}

// ---------------------------------------------------------------------------
// Confetti
// ---------------------------------------------------------------------------

/// Bursts confetti from [at] (global position) over everything.
void confetti(Offset at, {int count = 46}) {
  Fx.add(_Confetti(at: at, count: count), 2200);
}

class _Bit {
  final double vx, vy, spin, w, h;
  final Color c;
  _Bit(this.vx, this.vy, this.spin, this.w, this.h, this.c);
}

class _Confetti extends StatefulWidget {
  final Offset at;
  final int count;
  const _Confetti({required this.at, required this.count});
  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2100))..forward();
  late final List<_Bit> bits;
  static const _cols = [Color(0xFFB8692A), Color(0xFFF2A04A), Color(0xFFF26A21), Color(0xFF5FBF9A), Color(0xFFB58BE0), Color(0xFFF48AA0), Color(0xFFF6B300)];

  @override
  void initState() {
    super.initState();
    bits = List.generate(widget.count, (i) {
      final a = -pi / 2 + (_r() - .5) * pi * 1.1;
      final sp = 260 + _r() * 420;
      return _Bit(cos(a) * sp, sin(a) * sp, (_r() - .5) * 14, 6 + _r() * 6, 8 + _r() * 8, _cols[i % _cols.length]);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(painter: _ConfettiPainter(bits, widget.at, _c.value * 2.1)),
        ),
      );
}

class _ConfettiPainter extends CustomPainter {
  final List<_Bit> bits;
  final Offset at;
  final double t;
  _ConfettiPainter(this.bits, this.at, this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final fade = t > 1.5 ? (1 - (t - 1.5) / .6).clamp(0.0, 1.0) : 1.0;
    for (final b in bits) {
      final drag = exp(-1.2 * t);
      final x = at.dx + b.vx * (1 - drag) / 1.2;
      final y = at.dy + b.vy * (1 - drag) / 1.2 + 420 * t * t;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin * t);
      canvas.scale(1, cos(t * 9 + b.spin).abs() * .8 + .2);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: b.w, height: b.h), Paint()..color = b.c.withValues(alpha: fade));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter o) => true;
}
