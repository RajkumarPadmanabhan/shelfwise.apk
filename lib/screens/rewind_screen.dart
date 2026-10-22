import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../art.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../look.dart';
import '../services/share_image.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/common.dart';
import '../widgets/stars.dart';

/// Plays the story-style reading recap for 'month', 'year' or 'all'.
Future<void> openRewind(String period) {
  Sfx.play('swoosh');
  dropFocus();
  return navKey.currentState!.push(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 450),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => RewindScreen(period: period),
    transitionsBuilder: (_, a, _, c) {
      final t = CurvedAnimation(parent: a, curve: ease);
      return FadeTransition(opacity: t, child: ScaleTransition(scale: Tween(begin: .9, end: 1.0).animate(t), child: c));
    },
  ));
}

class _Slide {
  final Color bg, fg;
  final Widget Function() build;
  const _Slide(this.bg, this.fg, this.build);
}

class RewindScreen extends StatefulWidget {
  final String period;
  const RewindScreen({super.key, required this.period});
  @override
  State<RewindScreen> createState() => _RewindScreenState();
}

class _RewindScreenState extends State<RewindScreen> with TickerProviderStateMixin {
  late final AnimationController _prog = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200));
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  final _card = GlobalKey();
  late final List<_Slide> _slides;
  int _i = 0;

  String get p => widget.period;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _slides = _build();
    _prog.addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
    _prog.forward();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Look.overlay();
    _prog.dispose();
    _bob.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i < 0 || i >= _slides.length) return;
    setState(() => _i = i);
    Buzz.tick();
    if (i == _slides.length - 1) {
      _prog.value = 1;
      Sfx.play('trophy');
    } else {
      Sfx.play('swoosh');
      _prog.forward(from: 0);
    }
  }

  void _next() => _go(_i + 1);
  void _prev() => _i == 0 ? _prog.forward(from: 0) : _go(_i - 1);

  // ---------------- data → slides ----------------

  List<_Slide> _build() {
    final name = store.profile.first;
    final fin = store.finishedIn(p), added = store.addedIn(p);
    final todos = store.todosDoneIn(p), streak = store.streak(p), pages = store.pagesIn(p);
    final top = store.topShelf(p);
    final bars = store.barsFor(p);
    final best = bars.fold<(int, int)>((-1, 0), (a, e) => e.$2 > a.$2 ? (bars.indexOf(e), e.$2) : a);
    final badges = rewards.where((r) => store.claimed.contains(r.id)).toList();
    final secs = store.readSecondsIn(p);
    final rated = store.topRated(p);
    const fullMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    String bestLabel() {
      final l = bars[best.$1].$1;
      if (p == 'month') return 'week ${best.$1 + 1}';
      if (p == 'year') return fullMonths[best.$1];
      if (l.length == 4) return l;
      final ix = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].indexOf(l);
      return ix < 0 ? l : fullMonths[ix];
    }

    final unit = p == 'month' ? 'week' : (p == 'all' && bars.first.$1.length == 4 ? 'year' : 'month');
    const dark = Color(0xFF1C1C1C), cream = Color(0xFFF7F0E6), ink = Color(0xFF111111);
    final s = <_Slide>[
      _Slide(dark, cream, () => _intro(name)),
      if (fin.isNotEmpty) _Slide(const Color(0xFFFF4F0F), ink, () => _bigNumber('You finished', fin.length, fin.length == 1 ? 'book' : 'books', ink, covers: fin)),
      if (added.isNotEmpty)
        _Slide(const Color(0xFFF6B300), ink,
            () => _bigNumber(p == 'all' ? 'Your shelves hold' : 'You added', added.length, added.length == 1 ? 'book' : 'books', ink, covers: added, row: true)),
      if (best.$2 > 0 && bars.length > 1)
        _Slide(const Color(0xFFB6D8D5), ink, () => _best('Your biggest $unit was', bestLabel(), best.$2, bars, best.$1)),
      if (top != null) _Slide(const Color(0xFF1D4A37), Colors.white, () => _shelf(top.$1, top.$2)),
      if (pages > 0) _Slide(const Color(0xFFF5ECDF), ink, () => _bigNumber('You turned', pages, pages == 1 ? 'page in Shelfwise' : 'pages in Shelfwise', ink, emoji: '📖')),
      if (secs >= 600) _Slide(const Color(0xFF1B2A44), Colors.white, () => _time(secs)),
      if (rated != null) _Slide(const Color(0xFFF6B3C3), ink, () => _rated(rated)),
      if (p != 'month' && store.goalThisYear > 0) _Slide(const Color(0xFF5FBF9A), ink, () => _goal()),
      if (todos > 0 || streak > 1) _Slide(const Color(0xFF8A5A9E), Colors.white, () => _todos(todos, streak)),
      if (badges.isNotEmpty) _Slide(const Color(0xFF2F6F8F), Colors.white, () => _badges(badges)),
      if (fin.isEmpty && added.isEmpty) _Slide(const Color(0xFFF6B300), ink, () => _empty()),
      _Slide(const Color(0xFFF9EDD9), const Color(0xFF3A2A1C), () => _summary(name, fin, added, todos, streak, pages, top)),
    ];
    return s;
  }

  // ---------------- slides ----------------

  TextStyle _serif(double size, Color c) => TextStyle(fontFamily: F.serif, fontWeight: FontWeight.w800, fontSize: size, color: c, height: 1.02);
  TextStyle _num(double size, Color c) => TextStyle(
      fontFamily: F.serif, fontWeight: FontWeight.w800, fontSize: size, color: c, height: 1.08, fontFeatures: const [FontFeature.liningFigures()]);
  TextStyle _hand(double size, Color c) => TextStyle(fontFamily: F.hand, fontWeight: FontWeight.w700, fontSize: size, color: c);
  TextStyle _sans(double size, Color c, [FontWeight w = FontWeight.w800]) => TextStyle(fontFamily: F.nunito, fontWeight: w, fontSize: size, color: c, height: 1.25);

  Widget _intro(String name) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FadeIn(
          ms: 700,
          child: AnimatedBuilder(
            animation: _bob,
            builder: (_, c) => Transform.translate(offset: Offset(0, sin(_bob.value * 2 * pi) * 8), child: c),
            child: SvgPicture.string(owlSvg, width: 130, height: 118),
          ),
        ),
        const SizedBox(height: 22),
        FadeIn(delay: 200, child: Text('$name’s', style: _hand(36, C.orange))),
        FadeIn(delay: 350, child: Text('Reading\nRewind', textAlign: TextAlign.center, style: _serif(58, const Color(0xFFF7F0E6)))),
        const SizedBox(height: 18),
        FadeIn(
          delay: 550,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: C.orange, borderRadius: BorderRadius.circular(20)),
            child: Text(AppStore.periodLabel(p), style: _sans(15, const Color(0xFF111111))),
          ),
        ),
        const SizedBox(height: 40),
        FadeIn(delay: 900, child: Text('Tap to begin  ⟶', style: _sans(14, const Color(0x99F7F0E6), FontWeight.w700))),
      ]);

  Widget _count(int v, TextStyle style) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: v.toDouble()),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
        builder: (_, x, _) => Text('${x.round()}', style: style),
      );

  Widget _bigNumber(String top, int n, String unit, Color fg, {List<Item>? covers, bool row = false, String? emoji}) {
    final cv = (covers ?? const <Item>[]).take(5).toList();
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (emoji != null) ...[FadeIn(child: const _PageFlipper()), const SizedBox(height: 22)],
      FadeIn(child: Text(top, style: _sans(26, fg))),
      FadeIn(delay: 150, child: _count(n, _num(120, fg))),
      FadeIn(delay: 300, child: Text(unit, style: _sans(24, fg))),
      const SizedBox(height: 28),
      if (cv.isNotEmpty) SizedBox(height: 150, child: row ? _coverRow(cv) : _fan(cv)),
    ]);
  }

  Widget _fan(List<Item> cv) => Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [
        for (final (i, b) in cv.indexed)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 700 + i * 140),
            curve: Interval(i * 140 / (700 + i * 140), 1, curve: springCurve),
            builder: (_, v, c) {
              final mid = (cv.length - 1) / 2;
              final ang = (i - mid) * .26 * v;
              return Transform.translate(
                offset: Offset((i - mid) * 46 * v, -(1 - ((i - mid).abs() / max(1, mid))) * 14 * v + (1 - v) * 60),
                child: Transform.rotate(angle: ang, alignment: Alignment.bottomCenter, child: Opacity(opacity: v.clamp(0, 1), child: c)),
              );
            },
            child: _cover(b, 92, 132),
          ),
      ]);

  Widget _coverRow(List<Item> cv) => LayoutBuilder(builder: (_, c) {
        const w = 84.0;
        final step = cv.length <= 1 ? 0.0 : min(w + 8, (c.maxWidth - w) / (cv.length - 1));
        final left = (c.maxWidth - (w + step * (cv.length - 1))) / 2;
        return Stack(clipBehavior: Clip.none, children: [
          for (final (i, b) in cv.indexed)
            Positioned(
              left: left + i * step,
              bottom: 0,
              child: FadeIn(delay: 200 + i * 120, dy: 30, child: _cover(b, w, 120)),
            ),
        ]);
      });

  Widget _cover(Item b, double w, double h) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          boxShadow: const [BoxShadow(color: Color(0x59000000), offset: Offset(0, 8), blurRadius: 16)],
        ),
        child: BookCover(b, w: w, h: h, titleSize: 11, authorSize: 8),
      );

  Widget _best(String top, String label, int n, List<(String, int)> bars, int bi) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FadeIn(child: Text(top, style: _sans(24, const Color(0xFF111111)))),
        const SizedBox(height: 6),
        FadeIn(delay: 150, child: Text(label[0].toUpperCase() + label.substring(1), textAlign: TextAlign.center, style: _serif(54, const Color(0xFF111111)))),
        FadeIn(delay: 300, child: Text('${plural(n, 'book')} finished', style: _sans(20, const Color(0xFF111111), FontWeight.w700))),
        const SizedBox(height: 34),
        SizedBox(
          height: 170,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1400),
            curve: ease,
            builder: (_, v, _) => CustomPaint(size: const Size(double.infinity, 170), painter: _StoryBars(bars, bi, v)),
          ),
        ),
      ]);

  Widget _shelf(Collection c, int n) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FadeIn(child: Text('Your favourite shelf', style: _sans(24, Colors.white))),
        const SizedBox(height: 20),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: springCurve,
          builder: (_, v, c) => Transform.scale(scale: v, child: Transform.rotate(angle: (1 - v) * -.5, child: c)),
          child: Text(c.emoji, style: const TextStyle(fontSize: 96)),
        ),
        const SizedBox(height: 10),
        FadeIn(delay: 300, child: Text(c.name, textAlign: TextAlign.center, style: _serif(46, Colors.white))),
        const SizedBox(height: 8),
        FadeIn(delay: 450, child: Text(plural(n, 'book'), style: _hand(30, const Color(0xFFF2B84B)))),
        const SizedBox(height: 26),
        SizedBox(height: 132, child: _coverRow(c.books.take(4).toList())),
      ]);

  Widget _time(int secs) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FadeIn(child: _Clock()),
        const SizedBox(height: 24),
        FadeIn(delay: 150, child: Text('You read for', style: _sans(26, Colors.white))),
        FadeIn(delay: 300, child: Text(fmtDuration(secs), textAlign: TextAlign.center, style: _num(78, Colors.white))),
        FadeIn(delay: 450, child: Text('inside Shelfwise', style: _sans(22, Colors.white))),
      ]);

  Widget _rated(Item b) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FadeIn(child: Text('Your top-rated read', style: _sans(26, const Color(0xFF111111)))),
        const SizedBox(height: 22),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 800),
          curve: springCurve,
          builder: (_, v, c) => Transform.scale(scale: .6 + .4 * v, child: Transform.rotate(angle: (1 - v) * -.3, child: c)),
          child: _cover(b, 130, 186),
        ),
        const SizedBox(height: 20),
        FadeIn(delay: 300, child: Text(b.title, textAlign: TextAlign.center, style: _serif(34, const Color(0xFF111111)))),
        FadeIn(delay: 400, child: Text(b.author, style: _sans(17, const Color(0xFF111111), FontWeight.w700))),
        const SizedBox(height: 12),
        FadeIn(delay: 550, child: StarRating(value: b.rating, size: 34, empty: const Color(0x55111111))),
      ]);

  Widget _goal() {
    final done = store.finishedThisYear, goal = store.goalThisYear;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      FadeIn(child: Text('Your ${DateTime.now().year} goal', style: _sans(26, const Color(0xFF111111)))),
      const SizedBox(height: 24),
      SizedBox(
        width: 190,
        height: 190,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: (done / goal).clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 1500),
          curve: ease,
          builder: (_, v, _) => Stack(alignment: Alignment.center, children: [
            Positioned.fill(child: CircularProgressIndicator(value: v, strokeWidth: 16, color: const Color(0xFF111111), backgroundColor: const Color(0x33111111), strokeCap: StrokeCap.round)),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$done', style: _num(64, const Color(0xFF111111))),
              Text('of $goal books', style: _sans(16, const Color(0xFF111111))),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 22),
      FadeIn(delay: 600, child: Text(done >= goal ? 'Goal smashed. 🎉' : '${goal - done} more to go. You’ve got this.', style: _sans(18, const Color(0xFF111111)))),
    ]);
  }

  Widget _todos(int n, int streak) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FadeIn(child: Text('You ticked off', style: _sans(26, Colors.white))),
        FadeIn(delay: 150, child: _count(n, _num(120, Colors.white))),
        FadeIn(delay: 300, child: Text(n == 1 ? 'to-do' : 'to-dos', style: _sans(24, Colors.white))),
        const SizedBox(height: 22),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < min(n, 18); i++)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 400 + i * 70),
              curve: Interval(i * 70 / (400 + i * 70), 1, curve: popCurve),
              builder: (_, v, c) => Transform.scale(scale: v, child: c),
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(color: Color(0xFF5FBF9A), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 17),
              ),
            ),
        ]),
        if (streak > 1) ...[
          const SizedBox(height: 26),
          FadeIn(
            delay: 900,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(22)),
              child: Text('🔥 Longest streak: $streak days in a row', style: _sans(17, Colors.white)),
            ),
          ),
        ],
      ]);

  Widget _badges(List<Reward> b) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FadeIn(child: Text('Badges unlocked', style: _serif(44, Colors.white))),
        const SizedBox(height: 26),
        Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
          for (final (i, r) in b.indexed)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 500 + i * 120),
              curve: Interval(i * 120 / (500 + i * 120), 1, curve: popCurve),
              builder: (_, v, c) => Transform.scale(scale: v, child: c),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: const Color(0x29FFFFFF), borderRadius: BorderRadius.circular(18)),
                child: Text('${r.emoji} ${r.title}', style: _sans(16, Colors.white)),
              ),
            ),
        ]),
      ]);

  Widget _empty() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FadeIn(child: const Text('📖', style: TextStyle(fontSize: 90))),
        const SizedBox(height: 14),
        FadeIn(delay: 150, child: Text('Your story is\njust starting', textAlign: TextAlign.center, style: _serif(46, const Color(0xFF111111)))),
        const SizedBox(height: 14),
        FadeIn(delay: 300, child: Text('Add a book or finish one, and this Rewind fills up.', textAlign: TextAlign.center, style: _sans(17, const Color(0xFF111111), FontWeight.w700))),
      ]);

  Widget _summary(String name, List<Item> fin, List<Item> added, int todos, int streak, int pages, (Collection, int)? top) {
    final covers = (fin.isNotEmpty ? fin : added).take(5).toList();
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      FadeIn(child: Text('That’s a wrap, $name!', style: _serif(30, const Color(0xFF3A2A1C)))),
      const SizedBox(height: 18),
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 800),
        curve: springCurve,
        builder: (_, v, c) => Transform.scale(scale: .8 + .2 * v, child: Opacity(opacity: v.clamp(0, 1), child: c)),
        child: RepaintBoundary(
          key: _card,
          child: RewindCard(
            name: name,
            period: AppStore.periodLabel(p),
            covers: covers,
            stats: [
              ('📚', fin.length, 'finished'),
              ('➕', added.length, p == 'all' ? 'on shelves' : 'added'),
              ('✅', todos, 'to-dos done'),
              store.readSecondsIn(p) >= 3600
                  ? ('⏱️', store.readSecondsIn(p) ~/ 3600, 'hours reading')
                  : pages > 0
                      ? ('📖', pages, 'pages turned')
                      : ('🔥', streak, 'day streak'),
            ],
            topShelf: top == null ? null : '${top.$1.emoji} ${top.$1.name}',
          ),
        ),
      ),
      const SizedBox(height: 22),
      FadeIn(
        delay: 300,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Pill('Share', kind: Kind.pri, icon: const Icon(Icons.ios_share_rounded, color: Colors.white, size: 18), onTap: () {
            shareCard(_card, name: 'shelfwise-rewind', text: 'My ${AppStore.periodLabel(p)} reading Rewind on Shelfwise 📚');
          }),
          const SizedBox(width: 10),
          Pill('Save', icon: const Icon(Icons.download_rounded, size: 18, color: Color(0xFF3A2A1C)), onTap: () {
            saveCard(_card, name: 'shelfwise-rewind-${DateTime.now().millisecondsSinceEpoch}');
          }),
          const SizedBox(width: 10),
          Pill('Replay', kind: Kind.outline, onTap: () => _go(0)),
        ]),
      ),
    ]);
  }

  // ---------------- frame ----------------

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final s = _slides[_i];
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => d.localPosition.dx < mq.size.width * .3 ? _prev() : (_i < _slides.length - 1 ? _next() : null),
        onLongPressStart: (_) => _prog.stop(),
        onLongPressEnd: (_) {
          if (_i < _slides.length - 1) _prog.forward();
        },
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 400) Navigator.of(context).maybePop();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 450),
          curve: ease,
          color: s.bg,
          child: Stack(children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.fromLTRB(22, mq.padding.top + 70, 22, mq.padding.bottom + 30),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  switchInCurve: ease,
                  transitionBuilder: (c, a) => FadeTransition(
                    opacity: a,
                    child: ScaleTransition(scale: Tween(begin: .94, end: 1.0).animate(a), child: c),
                  ),
                  child: KeyedSubtree(key: ValueKey(_i), child: Center(child: SingleChildScrollView(child: s.build()))),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: mq.padding.top + 10,
              child: Column(children: [
                AnimatedBuilder(
                  animation: _prog,
                  builder: (_, _) => Row(children: [
                    for (var k = 0; k < _slides.length; k++)
                      Expanded(
                        child: Container(
                          height: 3.5,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(color: s.fg.withValues(alpha: .25), borderRadius: BorderRadius.circular(2)),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: k < _i ? 1 : (k == _i ? _prog.value : 0),
                            child: Container(decoration: BoxDecoration(color: s.fg, borderRadius: BorderRadius.circular(2))),
                          ),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Text('📚 Shelfwise Rewind', style: _sans(13, s.fg.withValues(alpha: .85))),
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: 'Close Rewind',
                    child: Pressable(
                      onTap: () => Navigator.of(context).maybePop(),
                      scale: .85,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: s.fg.withValues(alpha: .14), shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Icon(Icons.close_rounded, color: s.fg, size: 20),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A clock whose hands spin round (for the reading-time slide).
class _Clock extends StatefulWidget {
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(size: const Size(110, 110), painter: _ClockPainter(_c.value)),
      );
}

class _ClockPainter extends CustomPainter {
  final double t;
  _ClockPainter(this.t);
  @override
  void paint(Canvas c, Size s) {
    final o = s.center(Offset.zero), r = s.width / 2;
    c.drawCircle(o, r, Paint()..color = const Color(0x22FFFFFF));
    c.drawCircle(o, r - 4, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4);
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6;
      c.drawLine(o + Offset(cos(a), sin(a)) * (r - 12), o + Offset(cos(a), sin(a)) * (r - 18), Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round);
    }
    final hand = Paint()
      ..color = const Color(0xFFF2B84B)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final m = t * 2 * pi * 4 - pi / 2, h = t * 2 * pi / 3 - pi / 2;
    c.drawLine(o, o + Offset(cos(m), sin(m)) * (r - 20), hand);
    c.drawLine(o, o + Offset(cos(h), sin(h)) * (r - 36), hand..color = Colors.white);
    c.drawCircle(o, 6, Paint()..color = const Color(0xFFF2B84B));
  }

  @override
  bool shouldRepaint(_ClockPainter o) => o.t != t;
}

/// A little open book whose right-hand page keeps flipping over the spine.
class _PageFlipper extends StatefulWidget {
  const _PageFlipper();
  @override
  State<_PageFlipper> createState() => _PageFlipperState();
}

class _PageFlipperState extends State<_PageFlipper> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  static const _w = 74.0, _h = 96.0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _page({required bool left, double shade = 0}) => Container(
        width: _w,
        height: _h,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF7),
          borderRadius: BorderRadius.horizontal(left: Radius.circular(left ? 6 : 1), right: Radius.circular(left ? 1 : 6)),
          gradient: LinearGradient(
            begin: left ? Alignment.centerRight : Alignment.centerLeft,
            end: left ? Alignment.centerLeft : Alignment.centerRight,
            colors: [Color.lerp(const Color(0xFFE9DFCF), Colors.black, shade)!, Color.lerp(const Color(0xFFFFFDF7), Colors.black, shade)!],
            stops: const [0, .25],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var k = 0; k < 7; k++)
            Container(
              height: 3,
              width: k == 6 ? 28 : double.infinity,
              margin: const EdgeInsets.only(bottom: 7),
              decoration: BoxDecoration(color: Color.lerp(const Color(0xFFD9CDBB), Colors.black, shade), borderRadius: BorderRadius.circular(2)),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _w * 2 + 16,
      height: _h + 14,
      child: Stack(alignment: Alignment.center, children: [
        // cover peeking out behind the pages
        Container(
          width: _w * 2 + 16,
          height: _h + 12,
          decoration: BoxDecoration(
            color: const Color(0xFFB8692A),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Color(0x40000000), offset: Offset(0, 8), blurRadius: 14)],
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [_page(left: true), _page(left: false)]),
        AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final t = Curves.easeInOutCubic.transform((_c.value / .8).clamp(0.0, 1.0));
            final ang = -t * pi;
            final back = ang < -pi / 2;
            final shade = sin(t * pi) * .18;
            return Transform.translate(
              offset: const Offset(_w / 2, 0),
              child: Transform(
                alignment: Alignment.centerLeft,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, .0018)
                  ..rotateY(ang),
                child: back
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..scaleByDouble(-1, 1, 1, 1),
                        child: _page(left: true, shade: shade),
                      )
                    : _page(left: false, shade: shade),
              ),
            );
          },
        ),
      ]),
    );
  }
}

class _StoryBars extends CustomPainter {
  final List<(String, int)> bars;
  final int best;
  final double t;
  _StoryBars(this.bars, this.best, this.t);
  @override
  void paint(Canvas c, Size s) {
    final mx = max(1, bars.map((e) => e.$2).fold(0, max));
    final slot = s.width / bars.length, bw = min(34.0, slot * .64);
    for (final (i, (l, v)) in bars.indexed) {
      final tt = Curves.easeOutBack.transform(((t * 1.6 - i * .05)).clamp(0.0, 1.0));
      final h = v / mx * (s.height - 30) * tt;
      final x = i * slot + (slot - bw) / 2;
      c.drawRRect(RRect.fromLTRBR(x, s.height - 22 - max(h, 3), x + bw, s.height - 22, const Radius.circular(7)),
          Paint()..color = i == best ? const Color(0xFF111111) : const Color(0x55111111));
      final tp = TextPainter(
          text: TextSpan(text: l, style: const TextStyle(fontFamily: F.nunito, fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF111111))),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, Offset(x + bw / 2 - tp.width / 2, s.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(_StoryBars o) => o.t != t;
}

/// The shareable Rewind summary card.
class RewindCard extends StatelessWidget {
  final String name, period;
  final List<Item> covers;
  final List<(String, int, String)> stats;
  final String? topShelf;
  const RewindCard({super.key, required this.name, required this.period, required this.covers, required this.stats, this.topShelf});

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFF7F0E6);
    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1C1C1C), Color(0xFF34210F)]),
        boxShadow: const [BoxShadow(color: Color(0x40000000), offset: Offset(0, 12), blurRadius: 24)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Text('SHELFWISE REWIND', style: TextStyle(fontFamily: F.nunito, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 2, color: C.orange)),
          const Spacer(),
          SvgPicture.string(owlSvg, width: 40, height: 36),
        ]),
        Text('$name’s', style: const TextStyle(fontFamily: F.hand, fontWeight: FontWeight.w700, fontSize: 26, color: C.orange, height: 1)),
        Text(period, style: const TextStyle(fontFamily: F.serif, fontWeight: FontWeight.w800, fontSize: 28, color: cream, height: 1.1)),
        if (covers.isNotEmpty) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 66,
            child: Stack(children: [
              for (final (i, b) in covers.indexed)
                Positioned(
                  left: i * 34.0,
                  child: Transform.rotate(
                    angle: (i.isEven ? -1 : 1) * .05,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: const [BoxShadow(color: Color(0x66000000), offset: Offset(0, 3), blurRadius: 6)],
                      ),
                      child: BookCover(b, w: 46, h: 64, titleSize: 7, authorSize: 5, radius: 4),
                    ),
                  ),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.8,
          children: [
            for (final (i, (e, v, l)) in stats.indexed)
              Builder(builder: (_) {
                final t = tileColors[const [0, 2, 3, 1][i]];
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('$e $v', style: TextStyle(fontFamily: F.nunito, fontWeight: FontWeight.w800, fontSize: 21, color: t.fg)),
                    Text(l, style: TextStyle(fontFamily: F.nunito, fontWeight: FontWeight.w700, fontSize: 11.5, color: t.fg)),
                  ]),
                );
              }),
          ],
        ),
        if (topShelf != null) ...[
          const SizedBox(height: 12),
          Text('Favourite shelf · $topShelf', style: const TextStyle(fontFamily: F.nunito, fontWeight: FontWeight.w700, fontSize: 13, color: cream)),
        ],
        const SizedBox(height: 10),
        Text('📚 Shelfwise · ${fmtDate(DateTime.now().millisecondsSinceEpoch)}',
            style: const TextStyle(fontFamily: F.nunito, fontWeight: FontWeight.w700, fontSize: 10.5, color: Color(0xFFB2A290))),
      ]),
    );
  }
}
