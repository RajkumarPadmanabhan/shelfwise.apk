import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../art.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../icons.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/common.dart';

Route<void> tourRoute() => PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, _, _) => const Tour(replay: true),
      transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: c),
    );

class _Step {
  final String title, body;
  final List<String> tips;
  final Color panel;
  final Widget Function() art;
  final String pointerLabel;
  final bool pointsUp;
  const _Step(
    this.title,
    this.body,
    this.tips,
    this.panel,
    this.art, {
    required this.pointerLabel,
    this.pointsUp = false,
  });
}

class _AnimatedArrowPointer extends StatefulWidget {
  final String label;
  final bool pointsUp;
  const _AnimatedArrowPointer({required this.label, this.pointsUp = false});
  @override
  State<_AnimatedArrowPointer> createState() => _AnimatedArrowPointerState();
}

class _AnimatedArrowPointerState extends State<_AnimatedArrowPointer> with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, child) {
        final dy = (widget.pointsUp ? -1.0 : 1.0) * (_ac.value * 7);
        return Transform.translate(
          offset: Offset(0, dy),
          child: child,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: C.orange,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: C.orange.withValues(alpha: .38),
              blurRadius: 10,
              offset: Offset(0, widget.pointsUp ? -2 : 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.pointsUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: const TextStyle(
                fontFamily: F.sans,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: .2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A swipeable tour of everything Shelfwise can do, shown once after the intro.
class Tour extends StatefulWidget {
  final bool replay;
  const Tour({super.key, this.replay = false});
  @override
  State<Tour> createState() => _TourState();
}

class _TourState extends State<Tour> {
  final _pc = PageController();
  int _i = 0;

  late final List<_Step> _steps = [
    _Step(
      'Share & Notifications',
      'At the top right of your sanctuary, tap the Share icon near the notification bell to share your cozy bookshelves with friends. Tap the bell to see due to-dos, alerts, and reading rewards.',
      ['📤 Share icon near bell', '🔔 Due notifications', '🎁 Reading rewards'],
      const Color(0xFF1D4A37),
      () => const _ShareHeaderArt(),
      pointerLabel: 'Section 1: Top Bar & Share',
      pointsUp: true,
    ),
    _Step(
      'Cozy Shelves & One Bookmark',
      'Your books sit on wooden shelves just like at home. Open any book to read with page-curl animations. Each book keeps exactly one bookmark so you never lose your place. Once a book is finished, it clears from "Continue Reading" automatically.',
      ['🔖 1 bookmark per book', '✅ Finished clears continue reading', '📖 PDF & EPUB reader'],
      const Color(0xFFF5ECDF),
      () => const _ShelfArt(),
      pointerLabel: 'Section 2: Bookshelves & Bookmarks',
      pointsUp: false,
    ),
    _Step(
      'Shelf Styles, Stickers & Pets',
      'Personalize your sanctuary! Choose from 4 rich wood styles (Oak, Walnut, Pine, Rosewood), place movable stickers anywhere across your shelves, and play with cute pets that jump across platforms with sound effects.',
      ['🪵 4 wood finishes', '🪴 Movable stickers', '🐾 Playful pets with sounds'],
      const Color(0xFFB6D8D5),
      () => const _ShelvesAndPetsArt(),
      pointerLabel: 'Section 3: Styles, Stickers & Pets',
      pointsUp: false,
    ),
    _Step(
      'Double-Tap Navigation',
      'The bottom navigation features a single, sleek button. On the first page only the Home button is shown. Double-tap the "Home" button to switch directly to your full "Library". Double-tap "Library" to return Home.',
      ['✨ Single sleek button', '👆👆 Double-tap to toggle', '📚 Home ⇄ Library'],
      const Color(0xFF1C1C1C),
      () => const _DoubleTapNavArt(),
      pointerLabel: 'Section 4: Navigation Toggle',
      pointsUp: false,
    ),
    _Step(
      'Reading To-Dos & Smart Alerts',
      'Plan your reading schedule with to-dos. If a to-do is due today or starting soon, you get mobile notifications and a 1-hour start popup with OK and Skip buttons. Completing tasks unlocks milestone badges.',
      ['⏰ 1-hour start popups', '⭐ Star & prioritize', '🏆 Milestone badges'],
      const Color(0xFFF6B300),
      () => const _TodoArt(),
      pointerLabel: 'Section 5: Reading To-Dos & Alerts',
      pointsUp: false,
    ),
  ];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _finish() {
    Sfx.play('reset');
    if (widget.replay) {
      Navigator.of(context).pop();
      return;
    }
    store.toured = true;
    store.changed();
  }

  void _next() {
    Buzz.tick();
    if (_i == _steps.length - 1) return _finish();
    _pc.nextPage(duration: const Duration(milliseconds: 420), curve: ease);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final last = _i == _steps.length - 1;
    return Scaffold(
      backgroundColor: C.bg,
      body: Padding(
        padding: EdgeInsets.only(top: mq.padding.top, bottom: mq.padding.bottom),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 16, 4),
            child: Row(children: [
              const SizedBox(width: 2),
              SvgPicture.string(owlSvg, width: 34, height: 31),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shelfwise Walkthrough', style: nu(15, FontWeight.w800, C.ink)),
                  Text('Section ${_i + 1} of ${_steps.length}', style: nu(12, FontWeight.w600, C.muted)),
                ],
              ),
              const Spacer(),
              Pressable(
                onTap: _finish,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: C.brown.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: C.brown.withValues(alpha: .28), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Skip', style: nu(14, FontWeight.w800, C.brown)),
                      const SizedBox(width: 4),
                      Icon(Icons.fast_forward_rounded, size: 16, color: C.brown),
                    ],
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: _steps.length,
              onPageChanged: (i) {
                setState(() => _i = i);
                Sfx.play('swoosh');
              },
              itemBuilder: (_, i) => AnimatedBuilder(
                animation: _pc,
                builder: (_, _) {
                  final page = _pc.hasClients && _pc.position.haveDimensions ? _pc.page ?? 0 : 0.0;
                  return _page(_steps[i], (i - page).toDouble());
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 6, 26, 18),
            child: Row(children: [
              for (var k = 0; k < _steps.length; k++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: ease,
                  width: k == _i ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(color: k == _i ? C.brown : C.track, borderRadius: BorderRadius.circular(4)),
                ),
              const Spacer(),
              Pressable(
                onTap: _next,
                scale: .95,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: ease,
                  height: 54,
                  padding: EdgeInsets.symmetric(horizontal: last ? 26 : 22),
                  decoration: BoxDecoration(color: C.dark ? C.brown : C.black, borderRadius: BorderRadius.circular(6)),
                  alignment: Alignment.center,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(last ? (widget.replay ? 'Done' : 'Start reading') : 'Next',
                          key: ValueKey(last),
                          style: const TextStyle(fontFamily: F.hand, fontWeight: FontWeight.w500, fontSize: 25, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    const Text('⟶', style: TextStyle(fontSize: 20, color: C.orange)),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _page(_Step s, double off) {
    final fade = (1 - off.abs()).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, c) {
      final artH = min(c.maxHeight * .52, 360.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: _AnimatedArrowPointer(
              label: s.pointerLabel,
              pointsUp: s.pointsUp,
            ),
          ),
          Transform.translate(
            offset: Offset(off * -60, 0),
            child: Transform.scale(
              scale: .92 + .08 * fade,
              child: Container(
                height: artH,
                width: double.infinity,
                decoration: BoxDecoration(color: s.panel, borderRadius: BorderRadius.circular(28)),
                clipBehavior: Clip.antiAlias,
                child: s.art(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Opacity(
            opacity: fade,
            child: Transform.translate(
              offset: Offset(off * 40, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, style: TextStyle(fontFamily: F.serif, fontWeight: FontWeight.w800, fontSize: 28, color: C.ink, height: 1.1)),
                const SizedBox(height: 8),
                Text(s.body, style: nu(15, FontWeight.w600, C.body, 1.45)),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in s.tips)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(16)),
                      child: Text(t, style: nu(13, FontWeight.w800, C.chipText)),
                    ),
                ]),
              ]),
            ),
          ),
        ]),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Looping illustrations
// ---------------------------------------------------------------------------

/// Gives an illustration a repeating 0..1 clock.
abstract class _Loop extends StatefulWidget {
  final int ms;
  const _Loop(this.ms);
  Widget draw(BuildContext context, double t);
  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (context, _) => widget.draw(context, _c.value));
}

double _seg(double t, double a, double b, [Curve c = Curves.easeInOut]) => c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

class _ShareHeaderArt extends _Loop {
  const _ShareHeaderArt() : super(3000);
  @override
  Widget draw(BuildContext context, double t) {
    final pop = _seg(t, .2, .45, Curves.easeOutBack);
    final flash = (sin(t * pi * 4) * .5 + .5);
    return LayoutBuilder(builder: (_, c) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF235540),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rajkumar’s Sanctuary', style: nu(15, FontWeight.w800, Colors.white)),
                        Text('12 books on cozy shelves', style: nu(12, FontWeight.w600, const Color(0xFFB0D5C5))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: C.orange,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(color: C.orange.withValues(alpha: .4 * flash), blurRadius: 8, spreadRadius: 2),
                      ],
                    ),
                    child: SvgPicture.string(Ic.share, width: 17, height: 17, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E6B52),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SvgPicture.string(Ic.bell, width: 17, height: 17, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Transform.scale(
              scale: pop,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 6))],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.share_rounded, size: 20, color: C.orange),
                        const SizedBox(width: 8),
                        Text('Share your bookshelf!', style: nu(14, FontWeight.w800, C.ink)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap the Share icon near the bell to invite friends to see your reading sanctuary & books.',
                      textAlign: TextAlign.center,
                      style: nu(12.5, FontWeight.w600, C.muted, 1.3),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      );
    });
  }
}

class _ShelfArt extends _Loop {
  const _ShelfArt() : super(3200);
  static final _books = [
    Item(title: 'Pride and Prejudice', author: 'Jane Austen'),
    Item(title: 'The Hobbit', author: 'Tolkien'),
    Item(title: 'Circe', author: 'Madeline Miller'),
    Item(title: 'Dune', author: 'Frank Herbert'),
    Item(title: 'Rebecca', author: 'du Maurier'),
  ];
  @override
  Widget draw(BuildContext context, double t) {
    final lift = _seg(t, .1, .3) - _seg(t, .45, .65);
    final lit = t > .55 && t < .95;
    return LayoutBuilder(builder: (_, c) {
      const w = 64.0, h = 92.0;
      final left = (c.maxWidth - (w * 5 * .72 + w * .28 + 70)) / 2;
      final base = c.maxHeight * .72;
      return Stack(clipBehavior: Clip.none, children: [
        for (final (i, b) in _books.indexed)
          if (i != 2) _book(b, left + i * w * .72, base - h, w, h, 0),
        Positioned(
          left: left + 5 * w * .72 + 6,
          top: base - h * .85,
          child: GadgetView('lamp', w: 60, h: h * .85, lit: lit),
        ),
        Positioned(
          left: 18,
          right: 18,
          top: base - 46,
          height: 58,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [shelfPalettes[0][0], shelfPalettes[0][1], shelfPalettes[0][2]], stops: const [0, .55, 1]),
            ),
          ),
        ),
        _book(_books[2], left + 2 * w * .72, base - h, w, h, lift),
        Positioned(
          left: left + 2 * w * .72 + w * .5 - 8,
          top: base - h - 16 * lift - 12,
          child: Opacity(opacity: lift, child: const Text('🔖', style: TextStyle(fontSize: 18))),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: base - 34,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xD9FFF8EC), borderRadius: BorderRadius.circular(10)),
            child: Text('🔖 1 Bookmark per book · Finished clears continue reading', textAlign: TextAlign.center, style: nu(10.5, FontWeight.w800, lightPal.ink)),
          ),
        ),
        Positioned(
          left: left + 2 * w * .72 + w * .5 - 14,
          top: base + 22,
          child: Opacity(opacity: lift, child: const Text('👆', style: TextStyle(fontSize: 26))),
        ),
      ]);
    });
  }

  Widget _book(Item b, double x, double y, double w, double h, double lift) => Positioned(
        left: x,
        top: y,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(0, -16 * lift, 0, 1)
            ..rotateZ(-4 * pi / 180 * lift)
            ..scaleByDouble(1 + .1 * lift, 1 + .1 * lift, 1, 1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, .25 + .2 * lift), offset: Offset(0, 2 + 12 * lift), blurRadius: 6 + 14 * lift)],
            ),
            child: BookCover(b, w: w, h: h, titleSize: 9, authorSize: 6.5, shine: lift > 0 && lift < 1 ? lift : 0),
          ),
        ),
      );
}

class _ShelvesAndPetsArt extends _Loop {
  const _ShelvesAndPetsArt() : super(2800);
  @override
  Widget draw(BuildContext context, double t) {
    final petX = (sin(t * pi * 2) * .5 + .5);
    final petJump = (sin(t * pi * 4).abs() * 20);
    return LayoutBuilder(builder: (_, c) {
      final base = c.maxHeight * .68;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 20,
            right: 20,
            top: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final (i, name) in ['Oak', 'Walnut', 'Pine', 'Rosewood'].indexed)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 24,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: LinearGradient(
                            colors: [shelfPalettes[i % shelfPalettes.length][0], shelfPalettes[i % shelfPalettes.length][1]],
                          ),
                          border: Border.all(color: Colors.white.withValues(alpha: .6), width: 1.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(name, style: nu(10.5, FontWeight.w800, const Color(0xFF1E3A36))),
                    ],
                  ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: base,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: [shelfPalettes[1][0], shelfPalettes[1][1], shelfPalettes[1][2]]),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 6))],
              ),
            ),
          ),
          Positioned(
            left: 36,
            top: base - 44,
            child: const Text('🪴', style: TextStyle(fontSize: 34)),
          ),
          Positioned(
            right: 40,
            top: base - 56,
            child: Row(
              children: [
                Container(width: 14, height: 56, decoration: BoxDecoration(color: const Color(0xFF9E472A), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 4),
                Container(width: 16, height: 62, decoration: BoxDecoration(color: const Color(0xFF2F5233), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 4),
                Container(width: 13, height: 50, decoration: BoxDecoration(color: const Color(0xFFD4A373), borderRadius: BorderRadius.circular(3))),
              ],
            ),
          ),
          Positioned(
            left: 90 + petX * 70,
            top: base - 38 - petJump,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🎵', style: TextStyle(fontSize: 12 + petJump * .2)),
                    const SizedBox(width: 4),
                    const Text('🐾', style: TextStyle(fontSize: 10)),
                  ],
                ),
                Text(petX > .5 ? '🐱' : '🐶', style: const TextStyle(fontSize: 34)),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('🐾 Adopt pets · Move stickers · Pick shelf woods', style: nu(11.5, FontWeight.w800, const Color(0xFF1E3A36))),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _DoubleTapNavArt extends _Loop {
  const _DoubleTapNavArt() : super(3200);
  @override
  Widget draw(BuildContext context, double t) {
    final isLibrary = t > .5;
    final tapPop = (sin(t * pi * 4).abs() * .2);
    return LayoutBuilder(builder: (_, c) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '👆👆 Double-tap to toggle',
                style: nu(14, FontWeight.w800, Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            Transform.scale(
              scale: 1.0 + tapPop,
              child: Container(
                width: 170,
                height: 56,
                decoration: BoxDecoration(
                  color: isLibrary ? const Color(0xFF1D4A37) : const Color(0xFFFF5200),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: (isLibrary ? const Color(0xFF1D4A37) : const Color(0xFFFF5200)).withValues(alpha: .5),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(isLibrary ? '📚' : '🏠', style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Text(
                      isLibrary ? 'Library' : 'Home',
                      style: const TextStyle(fontFamily: F.hand, fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x22FFFFFF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                isLibrary ? 'Showing: Full Library Shelves' : 'Showing: Cozy Home Sanctuary',
                style: nu(12.5, FontWeight.w600, const Color(0xFFDDD0BA)),
              ),
            ),
          ],
        ),
      );
    });
  }
}


class _TodoArt extends _Loop {
  const _TodoArt() : super(2800);
  @override
  Widget draw(BuildContext context, double t) {
    final check = _seg(t, .2, .35, popCurve);
    final star = _seg(t, .5, .62, popCurve);
    Widget tile(Color bg, Color fg, double w, double h, {bool big = false, double done = 0, double starred = 0}) => Container(
          width: w,
          height: h,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: w * .5, height: big ? 10 : 7, decoration: BoxDecoration(color: fg.withValues(alpha: .85), borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 6),
            Container(width: w * .7, height: big ? 10 : 7, decoration: BoxDecoration(color: fg.withValues(alpha: .85), borderRadius: BorderRadius.circular(4))),
            const Spacer(),
            Row(children: [
              Transform.scale(
                scale: 1 + .3 * sin(done * pi),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done > .5 ? const Color(0xFF5FBF9A) : Colors.transparent,
                    border: Border.all(color: done > .5 ? const Color(0xFF5FBF9A) : fg, width: 2),
                  ),
                  child: done > .5 ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                ),
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: 1 + .3 * sin(starred * pi),
                child: Icon(starred > .5 ? Icons.star_rounded : Icons.star_border_rounded, size: 22, color: fg),
              ),
            ]),
          ]),
        );
    return LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth - 40;
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Stack(clipBehavior: Clip.none, children: [
          Column(children: [
            tile(const Color(0xFFFF4F0F), const Color(0xFF111111), w, c.maxHeight * .44, big: true, done: check),
            const SizedBox(height: 10),
            Row(children: [
              tile(const Color(0xFFF5ECDF), const Color(0xFF111111), (w - 10) / 2, c.maxHeight * .34, starred: star),
              const SizedBox(width: 10),
              tile(const Color(0xFF1D4A37), Colors.white, (w - 10) / 2, c.maxHeight * .34),
            ]),
          ]),
          for (var i = 0; i < 10; i++)
            Positioned(
              left: 18 + cos(i * .63) * 70 * check + 4,
              top: c.maxHeight * .44 - 50 - sin(i * .63).abs() * 60 * check + 40 * check * check,
              child: Opacity(
                opacity: (check * (1 - _seg(t, .45, .6))).clamp(0, 1),
                child: Container(width: 6, height: 8, color: const [Color(0xFFB8692A), Color(0xFF5FBF9A), Color(0xFFB58BE0), Color(0xFFF6B300)][i % 4]),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: Row(
                children: [
                  const Text('⏰', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Rebecca starts in 1 hr', style: nu(11, FontWeight.w800, C.ink)),
                        Text('Pop-up alert reminder', style: nu(9.5, FontWeight.w600, C.muted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFEFE8DD), borderRadius: BorderRadius.circular(6)),
                    child: Text('OK', style: nu(10, FontWeight.w800, C.ink)),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFEFE8DD), borderRadius: BorderRadius.circular(6)),
                    child: Text('Skip', style: nu(10, FontWeight.w800, C.muted)),
                  ),
                ],
              ),
            ),
          ),
        ]),
      );
    });
  }
}


