import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../art.dart';
import '../data/store.dart';
import '../icons.dart';
import '../services/share_image.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'bell.dart';
import 'rewind_screen.dart';

class StatsUi {
  static String period = 'all';
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with TickerProviderStateMixin {
  late final AnimationController _bars = AnimationController(vsync: this, duration: const Duration(milliseconds: 1150))..forward();
  late final AnimationController _donut = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..forward();
  late final AnimationController _line = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
  late final AnimationController _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  int _range = 7;

  @override
  void dispose() {
    _bars.dispose();
    _donut.dispose();
    _line.dispose();
    _shine.dispose();
    super.dispose();
  }

  void _period(String p) {
    setState(() => StatsUi.period = p);
    _bars.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = StatsUi.period;
        final read = store.finishedIn(p).length, added = store.addedIn(p).length;
        final total = store.totalBooks, reading = store.readingCount, finishedAll = store.finishedCount;
        final bars = store.barsFor(p);
        final act = store.activity(_range);
        final barTitle = switch (p) {
          'month' => 'Books finished by week',
          'year' => 'Books finished by month',
          _ => bars.first.$1.length == 4 ? 'Books finished by year' : 'Books finished by month',
        };
        return Stack(children: [
          ListView(
            padding: EdgeInsets.fromLTRB(22, mq.padding.top + 26, 22, 110),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Expanded(child: H1('Stats')),
              Semantics(
                  button: true,
                  label: 'Share your stats',
                  child: Pressable(
                    onTap: () => _shareStats(p),
                    scale: .9,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: C.softBrown, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: SvgIcon(Ic.share, color: C.dark ? C.chipText : const Color(0xFF6D4A2B), size: 21),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const BellButton(),
              ]),
              const SizedBox(height: 2),
              Text('Your reading at a glance', style: nu(14, FontWeight.w600, C.muted)),
              const SizedBox(height: 14),
              Row(children: [
                for (final (k, l) in const [('month', 'This month'), ('year', 'This year'), ('all', 'All time')]) ...[
                  PopChip(l, on: p == k, fontSize: 13, pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), onTap: () => _period(k)),
                  const SizedBox(width: 8),
                ],
              ]),
              const SizedBox(height: 14),
              Row(children: [
                _tile(read, 'Books read'),
                const SizedBox(width: 10),
                _tile(p == 'all' ? total : added, p == 'all' ? 'On shelves' : 'Books added'),
                const SizedBox(width: 10),
                _tile(store.todosDoneIn(p), 'To-dos done'),
              ]),
              const SizedBox(height: 14),
              _rewindCard(p),
              const H2('Reading time', pad: EdgeInsets.fromLTRB(0, 24, 0, 10)),
              _timeCard(p),
              H2('${DateTime.now().year} reading goal', pad: const EdgeInsets.fromLTRB(0, 24, 0, 10)),
              _goalCard(),
              H2(barTitle, pad: const EdgeInsets.fromLTRB(0, 24, 0, 10)),
              CardBox(
                child: AspectRatio(
                  aspectRatio: 300 / 135,
                  child: AnimatedBuilder(
                    animation: _bars,
                    builder: (_, _) => CustomPaint(painter: _Bars(bars, _bars.value * 1150)),
                  ),
                ),
              ),
              const H2('Your library', pad: EdgeInsets.fromLTRB(0, 24, 0, 10)),
              CardBox(
                child: Row(children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: AnimatedBuilder(
                      animation: _donut,
                      builder: (_, _) => CustomPaint(painter: _Donut(finishedAll, reading, total, Curves.easeOutCubic.transform(_donut.value))),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(children: [
                      _legend(C.brown, 'Finished', finishedAll),
                      const SizedBox(height: 10),
                      _legend(const Color(0xFFF2A04A), 'Reading', reading),
                      const SizedBox(height: 10),
                      _legend(C.chip, 'Total', total),
                    ]),
                  ),
                ]),
              ),
              const H2('Activity', pad: EdgeInsets.fromLTRB(0, 24, 0, 4)),
              Text('Books added or finished and to-dos ticked off', style: nu(13, FontWeight.w600, C.muted)),
              const SizedBox(height: 10),
              Row(children: [
                for (final r in [7, 30]) ...[
                  PopChip('$r days',
                      on: _range == r,
                      fontSize: 13,
                      pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      onTap: () {
                        setState(() => _range = r);
                        _line.forward(from: 0);
                      }),
                  const SizedBox(width: 8),
                ],
              ]),
              const SizedBox(height: 10),
              CardBox(
                child: AspectRatio(
                  aspectRatio: 300 / 120,
                  child: AnimatedBuilder(
                    animation: _line,
                    builder: (_, _) => CustomPaint(painter: _Line(act, _line.value, _range)),
                  ),
                ),
              ),
            ],
          ),
        ]);
      },
    );
  }

  Widget _rewindCard(String p) {
    return Semantics(
      button: true,
      label: 'Play your reading Rewind',
      child: Pressable(
        onTap: () => openRewind(p),
        scale: .97,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            height: 92,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1C1C1C), Color(0xFF3A2416), Color(0xFFB8692A)], stops: [0, .55, 1]),
            ),
            child: Stack(children: [
              AnimatedBuilder(
                animation: _shine,
                builder: (_, _) => FractionalTranslation(
                  translation: Offset(-1.2 + _shine.value * 2.4, 0),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1, -.4),
                        end: Alignment(1, .4),
                        colors: [Color(0x00FFFFFF), Color(0x26FFFFFF), Color(0x00FFFFFF)],
                        stops: [.35, .5, .65],
                      ),
                    ),
                    child: SizedBox.expand(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(children: [
                  const Text('🎞️', style: TextStyle(fontSize: 34)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Your Rewind', style: TextStyle(fontFamily: F.serif, fontWeight: FontWeight.w800, fontSize: 21, color: Color(0xFFF7F0E6))),
                      Text('${AppStore.periodLabel(p)} · tap to play your reading story',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(12.5, FontWeight.w700, const Color(0xFFE9D9C4))),
                    ]),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: C.orange, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _timeCard(String p) {
    final secs = store.readSecondsIn(p);
    final mins = store.readMinutes(7);
    final top = mins.fold(0, max);
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final today = DateTime.now().weekday;
    return CardBox(
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(secs < 60 ? '0 min' : fmtDuration(secs), style: nu(26, FontWeight.w800)),
            Text(secs < 60 ? 'Open a book’s PDF or EPUB to start counting' : 'spent reading in Shelfwise',
                style: nu(12.5, FontWeight.w700, C.muted, 1.3)),
          ]),
        ),
        const SizedBox(width: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.only(left: 5),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: top == 0 ? 0 : mins[i] / top),
                  duration: Duration(milliseconds: 600 + i * 60),
                  curve: ease,
                  builder: (_, v, _) => Container(
                    width: 12,
                    height: 4 + 46 * v,
                    decoration: BoxDecoration(color: i == 6 ? C.brown : C.brown.withValues(alpha: .45), borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(days[(today - 7 + i) % 7], style: nu(10, FontWeight.w800, C.muted)),
              ]),
            ),
        ]),
      ]),
    );
  }

  Widget _goalCard() {
    final goal = store.goalThisYear, done = store.finishedThisYear;
    final p = goal == 0 ? 0.0 : (done / goal).clamp(0.0, 1.0);
    return Pressable(
      onTap: _setGoal,
      scale: .98,
      child: CardBox(
        child: Row(children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: p),
                  duration: const Duration(milliseconds: 1000),
                  curve: ease,
                  builder: (_, v, _) => CircularProgressIndicator(value: v, strokeWidth: 8, color: C.brown, backgroundColor: C.chip, strokeCap: StrokeCap.round),
                ),
              ),
              Text(goal == 0 ? '🎯' : '${(p * 100).round()}%', style: nu(goal == 0 ? 22 : 13, FontWeight.w800)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(goal == 0 ? 'Set a goal for ${DateTime.now().year}' : '$done of $goal books', style: nu(17, FontWeight.w800)),
              Text(
                goal == 0
                    ? 'How many books do you want to finish this year?'
                    : done >= goal
                        ? 'Goal reached! Tap to raise the bar.'
                        : '${goal - done} to go. Tap to change the goal.',
                style: nu(12.5, FontWeight.w700, C.muted, 1.3),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  void _setGoal() {
    final t = TextEditingController(text: store.goalThisYear == 0 ? '' : '${store.goalThisYear}');
    openDialog((ctx) => StatefulBuilder(
          builder: (ctx, set) => AppDialog(title: '${DateTime.now().year} reading goal', children: [
            const Sub('Books you’d like to finish this year. Finished books count automatically.'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in [6, 12, 24, 52])
                PopChip('$n', on: t.text == '$n', fontSize: 14, pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 9), onTap: () => set(() => t.text = '$n')),
            ]),
            const SizedBox(height: 8),
            AppInput(t, 'Or type a number', maxLength: 4, type: TextInputType.number, onChanged: (_) => set(() {})),
          ], actions: [
            if (store.goalThisYear > 0)
              Btn('Remove', kind: Kind.dng, onTap: () {
                store.setGoal(0);
                toast('Goal removed');
                return true;
              }),
            const Btn('Cancel'),
            Btn('Save', kind: Kind.pri, onTap: () {
              final n = int.tryParse(t.text.trim()) ?? 0;
              if (n <= 0) return false;
              store.setGoal(n);
              Sfx.play('pop');
              toast('Goal set: $n books in ${DateTime.now().year}');
              return true;
            }),
          ]),
        ));
  }

  void _shareStats(String p) {
    final key = GlobalKey();
    final read = store.finishedIn(p).length, added = store.addedIn(p).length;
    openDialog((ctx) => AppDialog(title: 'Share your stats', maxWidth: 380, children: [
          const Sub('Here’s the card that will be shared.'),
          Center(
            child: RepaintBoundary(
              key: key,
              child: StatsCard(
                name: store.profile.first,
                period: AppStore.periodLabel(p),
                stats: [
                  ('📚', read, 'books finished'),
                  ('➕', p == 'all' ? store.totalBooks : added, p == 'all' ? 'on my shelves' : 'books added'),
                  ('✅', store.todosDoneIn(p), 'to-dos done'),
                  store.readSecondsIn(p) >= 3600
                      ? ('⏱️', store.readSecondsIn(p) ~/ 3600, 'hours reading')
                      : ('🔥', store.streak(p), 'day streak'),
                ],
                bars: store.barsFor(p),
              ),
            ),
          ),
        ], actions: [
          Btn('Save', onTap: () async {
            await saveCard(key, name: 'shelfwise-stats-${DateTime.now().millisecondsSinceEpoch}');
            return false;
          }),
          Btn('Share', kind: Kind.pri, onTap: () async {
            await shareCard(key, name: 'shelfwise-stats', text: 'My reading stats on Shelfwise 📚 (${AppStore.periodLabel(p)})');
            return false;
          }),
          const Btn('Close'),
        ]));
  }

  Widget _tile(int v, String label) => Expanded(
        child: CardBox(
          pad: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Column(children: [
            TweenAnimationBuilder<double>(
              key: ValueKey('$label${StatsUi.period}'),
              tween: Tween(begin: 0, end: v.toDouble()),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, x, _) => Text(
                x.round().toString(),
                style: nu((MediaQuery.sizeOf(context).width * .06).clamp(20.0, 24.0), FontWeight.w800),
              ),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(12, FontWeight.w700, C.muted)),
          ]),
        ),
      );

  Widget _legend(Color c, String l, int n) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(l, style: nu(14, FontWeight.w700)),
        const Spacer(),
        Text('$n', style: nu(14, FontWeight.w800)),
      ]);
}

/// The shareable stats image (fixed light colours so it looks the same everywhere).
class StatsCard extends StatelessWidget {
  final String name, period;
  final List<(String, int, String)> stats;
  final List<(String, int)> bars;
  const StatsCard({super.key, required this.name, required this.period, required this.stats, required this.bars});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF3A2A1C);
    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFF8EC), Color(0xFFF2DFC2)]),
        border: Border.all(color: const Color(0xFFE8D8BF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$name’s reading', style: const TextStyle(fontFamily: F.serif, fontWeight: FontWeight.w800, fontSize: 22, color: ink, height: 1.1)),
              Text(period, style: const TextStyle(fontFamily: F.hand, fontWeight: FontWeight.w700, fontSize: 20, color: C.orange)),
            ]),
          ),
          SvgPicture.string(owlSvg, width: 52, height: 47),
        ]),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.75,
          children: [
            for (final (i, (e, v, l)) in stats.indexed)
              Builder(builder: (_) {
                final t = tileColors[i == 3 ? 4 : i];
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('$e $v', style: TextStyle(fontFamily: F.nunito, fontWeight: FontWeight.w800, fontSize: 22, color: t.fg)),
                    Text(l, style: TextStyle(fontFamily: F.nunito, fontWeight: FontWeight.w700, fontSize: 11.5, color: t.fg)),
                  ]),
                );
              }),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(height: 70, width: 264, child: CustomPaint(painter: MiniBars(bars))),
        const SizedBox(height: 10),
        const Row(children: [
          Text('📚 Shelfwise', style: TextStyle(fontFamily: F.nunito, fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFFB8692A))),
          Spacer(),
          Text('cozy shelves & reading to-dos', style: TextStyle(fontFamily: F.nunito, fontWeight: FontWeight.w700, fontSize: 10.5, color: Color(0xFF7D6F62))),
        ]),
      ]),
    );
  }
}

class MiniBars extends CustomPainter {
  final List<(String, int)> bars;
  final Color color, label;
  MiniBars(this.bars, {this.color = const Color(0xFFB8692A), this.label = const Color(0xFF7D6F62)});
  @override
  void paint(Canvas c, Size s) {
    final mx = max(1, bars.map((e) => e.$2).fold(0, max));
    final slot = s.width / bars.length, bw = min(26.0, slot * .62);
    for (final (i, (l, v)) in bars.indexed) {
      final h = v / mx * (s.height - 18);
      final x = i * slot + (slot - bw) / 2;
      c.drawRRect(RRect.fromLTRBR(x, s.height - 14 - max(h, 2), x + bw, s.height - 14, const Radius.circular(4)), Paint()..color = color);
      final tp = TextPainter(
          text: TextSpan(text: l, style: TextStyle(fontFamily: F.nunito, fontSize: 9, fontWeight: FontWeight.w700, color: label)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, Offset(x + bw / 2 - tp.width / 2, s.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(MiniBars o) => true;
}

TextPainter _tp(String s, double size, {Color? color, FontWeight w = FontWeight.w700}) =>
    TextPainter(text: TextSpan(text: s, style: nu(size, w, color ?? C.muted)), textDirection: TextDirection.ltr)..layout();

class _Bars extends CustomPainter {
  final List<(String, int)> m;
  final double ms;
  _Bars(this.m, this.ms);
  static const _e = Cubic(.2, .8, .2, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 300;
    canvas.scale(k);
    final mx = max(1, m.map((e) => e.$2).fold(0, max));
    final slot = 300 / m.length;
    final bw = min(30.0, slot * .6);
    final stagger = m.length > 6 ? 45 : 90;
    for (final (i, (label, v)) in m.indexed) {
      final t = _e.transform(((ms - i * stagger) / 700).clamp(0.0, 1.0));
      final h = v / mx * 90 * t;
      final x = i * slot + (slot - bw) / 2;
      if (h > 0) {
        canvas.drawRRect(RRect.fromLTRBR(x, 110 - h, x + bw, 110, Radius.circular(min(6, h / 2))), Paint()..color = C.brown);
      } else {
        canvas.drawRRect(RRect.fromLTRBR(x, 108, x + bw, 110, const Radius.circular(1)), Paint()..color = C.chip);
      }
      final vt = _tp('$v', 11);
      vt.paint(canvas, Offset(x + bw / 2 - vt.width / 2, 104 - max(h, 2) - vt.height + 2));
      final lt = _tp(label, 11);
      lt.paint(canvas, Offset(x + bw / 2 - lt.width / 2, 128 - lt.height + 2));
    }
  }

  @override
  bool shouldRepaint(_Bars o) => true;
}

class _Donut extends CustomPainter {
  final int read, reading, total;
  final double t;
  _Donut(this.read, this.reading, this.total, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 120;
    canvas.scale(k);
    const c = Offset(60, 60);
    final rect = Rect.fromCircle(center: c, radius: 48);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16;
    canvas.drawCircle(c, 48, p..color = C.chip);
    final used = max(1, read + reading);
    final a1 = read / used * 2 * pi, a2 = reading / used * 2 * pi;
    if (a1 > 0) canvas.drawArc(rect, -pi / 2, a1 * t, false, p..color = C.brown);
    if (a2 > 0) canvas.drawArc(rect, -pi / 2 + a1, a2 * t, false, p..color = const Color(0xFFF2A04A));
    final n = _tp('$total', 22, color: C.ink, w: FontWeight.w800);
    n.paint(canvas, Offset(60 - n.width / 2, 58 - n.height + 4));
    final l = _tp(total == 1 ? 'book' : 'books', 11);
    l.paint(canvas, Offset(60 - l.width / 2, 74 - l.height + 2));
  }

  @override
  bool shouldRepaint(_Donut o) => true;
}

class _Line extends CustomPainter {
  final List<int> v;
  final double t;
  final int range;
  _Line(this.v, this.t, this.range);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 300;
    canvas.scale(k);
    final grid = Paint()
      ..color = C.line
      ..strokeWidth = 1;
    for (final y in [20.0, 60.0, 100.0]) {
      canvas.drawLine(Offset(0, y), Offset(300, y), grid);
    }
    final mn = v.reduce(min).toDouble(), mx = v.reduce(max).toDouble();
    final pts = [
      for (final (i, y) in v.indexed) Offset(i / (v.length - 1) * 300, 100 - (y - mn) / ((mx - mn) == 0 ? 1 : (mx - mn)) * 80),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final fade = Curves.ease.transform(t.clamp(0.0, 1.0));
    final area = Path.from(path)
      ..lineTo(300, 100)
      ..lineTo(0, 100)
      ..close();
    canvas.drawPath(area, Paint()..color = C.brown.withValues(alpha: .15 * fade));
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * Curves.ease.transform(t)),
      Paint()
        ..color = C.brown
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(pts.last, 5, Paint()..color = C.brown.withValues(alpha: fade));
    final peak = v.reduce(max);
    if (peak > 0) {
      final pk = _tp('best day: $peak', 10, color: C.brown, w: FontWeight.w800);
      pk.paint(canvas, Offset(300 - pk.width, 4));
    }
    final a = _tp('$range days ago', 11);
    a.paint(canvas, Offset(0, 116 - a.height + 2));
    final b = _tp('Today', 11);
    b.paint(canvas, Offset(300 - b.width, 116 - b.height + 2));
  }

  @override
  bool shouldRepaint(_Line o) => true;
}
