import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../art.dart';
import '../data/store.dart';
import '../look.dart';
import '../services/auth_service.dart';
import '../services/notify.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/common.dart';

Route<void> introRoute() => PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, _, _) => const Onboarding(replay: true),
      transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: c),
    );

/// Welcome → Google sign in → notifications. Shown on first open (and from "Replay intro").
class Onboarding extends StatefulWidget {
  final bool replay;
  const Onboarding({super.key, this.replay = false});
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  int _step = 0;
  late final _email = TextEditingController(text: widget.replay ? store.profile.email : '');
  bool _sample = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => Look.overlay(forceDarkIcons: true));
  }

  @override
  void dispose() {
    _email.dispose();
    Look.overlay();
    super.dispose();
  }

  void _next() {
    Buzz.tick();
    setState(() => _step++);
  }

  void _finish() {
    final em = _email.text.trim();
    if (widget.replay) {
      if (em.isNotEmpty && em != store.profile.email) {
        final n = AppStore.nameFromEmail(em);
        store.profile
          ..email = em
          ..name = n
          ..handle = AppStore.handleFor(n);
        store.changed();
      }
      Navigator.of(context).pop();
      return;
    }
    store.setupFresh(sample: _sample, email: em);
    Sfx.play('reset');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.replay && _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step--);
      },
      child: Scaffold(
        backgroundColor: C.cream,
        resizeToAvoidBottomInset: true,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: ease,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(position: Tween(begin: const Offset(.08, 0), end: Offset.zero).animate(a), child: c),
          ),
          child: switch (_step) {
            0 => _Welcome(
                key: const ValueKey(0),
                email: _email,
                replay: widget.replay,
                sample: _sample,
                onSample: (v) => setState(() => _sample = v),
                onSelectEmail: (em) {
                  _email.text = em;
                  _finish();
                },
              ),
            1 => _GoogleStep(
                key: const ValueKey(1),
                email: _email,
                replay: widget.replay,
                sample: _sample,
                onSample: (v) => setState(() => _sample = v),
                onGo: _next,
              ),
            _ => _NotifyStep(key: const ValueKey(2), onDone: _finish),
          },
        ),
      ),
    );
  }
}

/// Scrollable, vertically centred page body with the mockup's phone padding.
class _Page extends StatelessWidget {
  final List<Widget> children;
  const _Page({required this.children});
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (_, c) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(0, max(28, mq.padding.top), 0, max(28, mq.padding.bottom)),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight - max(28, mq.padding.top) - max(28, mq.padding.bottom)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}

/// The black call-to-action with an orange arrow (and optional leading icon).
class _Cta extends StatefulWidget {
  final String label;
  final Widget trailing;
  final Widget? leading;
  final VoidCallback onTap;
  const _Cta(this.label, {required this.onTap, this.leading, this.trailing = const Text('⟶', style: TextStyle(fontFamily: F.hand, fontSize: 26, color: C.orange))});
  @override
  State<_Cta> createState() => _CtaState();
}

class _CtaState extends State<_Cta> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .98 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 60,
            margin: const EdgeInsets.symmetric(horizontal: 26),
            decoration: BoxDecoration(color: _down ? const Color(0xFF2E2E2E) : C.black, borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 12),
              ],
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(widget.label,
                      key: ValueKey(widget.label),
                      maxLines: 1,
                      style: const TextStyle(fontFamily: F.hand, fontWeight: FontWeight.w500, fontSize: 26, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 14),
              widget.trailing,
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

const googleLogoSvg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
  <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
  <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
  <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>''';

class _Welcome extends StatefulWidget {
  final TextEditingController email;
  final bool replay;
  final bool sample;
  final ValueChanged<bool> onSample;
  final ValueChanged<String> onSelectEmail;
  const _Welcome({
    super.key,
    required this.email,
    required this.replay,
    required this.sample,
    required this.onSample,
    required this.onSelectEmail,
  });
  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> with TickerProviderStateMixin {
  late final AnimationController _float = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
  late final AnimationController _line = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 750), () {
      if (mounted) _line.forward();
    });
  }

  @override
  void dispose() {
    _float.dispose();
    _line.dispose();
    super.dispose();
  }

  Future<void> _openGoogleChooser() async {
    Buzz.tick();
    try {
      final userCred = await AuthService.signInWithGoogle();
      if (userCred != null && userCred.user != null) {
        final email = userCred.user!.email ?? '';
        if (email.isNotEmpty) {
          widget.onSelectEmail(email);
        }
      }
    } catch (e) {
      debugPrint('Google sign in error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final artW = min(mq.size.width, mq.size.height * .46 * 345 / 400);
    final still = mq.disableAnimations;
    const phases = [0.0, .35, .7, .15, .55];
    return _Page(children: [
      FadeIn(
        ms: 650,
        dy: 20,
        child: Center(
          child: SizedBox(
            width: artW,
            height: artW * 400 / 345,
            child: Stack(children: [
              Positioned.fill(child: SvgPicture.string(welcomeReader)),
              for (final (i, b) in welcomeBooks.indexed)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _float,
                    builder: (_, c) {
                      final t = still ? 0.0 : sin((_float.value + phases[i]) * 2 * pi);
                      return Transform.translate(
                        offset: Offset(0, t * 4 * artW / 345),
                        child: Transform.rotate(angle: t * .012, child: c),
                      );
                    },
                    child: SvgPicture.string(b),
                  ),
                ),
              Positioned(
                left: 26 * artW / 345,
                top: 8 * artW / 345,
                child: Transform.rotate(
                  angle: -7 * pi / 180,
                  alignment: Alignment.topLeft,
                  child: Text('Different\nstories\nBrighter\ndays',
                      style: TextStyle(fontFamily: F.hand, fontWeight: FontWeight.w700, fontSize: 20 * artW / 345, height: 1, color: C.black)),
                ),
              ),
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(26, 14, 26, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FadeIn(
            delay: 150,
            child: Text('People\nwho read',
                style: TextStyle(
                    fontFamily: F.serif,
                    fontWeight: FontWeight.w800,
                    fontSize: mq.size.width <= 360 ? 38 : 44,
                    height: 1.02,
                    letterSpacing: -.5,
                    color: C.black)),
          ),
          const SizedBox(height: 6),
          FadeIn(
            delay: 300,
            child: IntrinsicWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('live different lives.',
                    style: TextStyle(fontFamily: F.hand, fontWeight: FontWeight.w500, fontSize: 30, color: C.orange, height: 1.1)),
                SizedBox(
                  height: 8,
                  child: AnimatedBuilder(animation: _line, builder: (_, _) => CustomPaint(painter: _Underline(Curves.easeInOut.transform(_line.value)))),
                ),
              ]),
            ),
          ),
        ]),
      ),
      FadeIn(
        delay: 450,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(40, 20, 40, 0),
          child: Text(
            'Keep every book you love on cozy shelves, and every reading plan on your to-do list.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: F.sans, fontSize: 15, height: 1.45, color: Color(0xFF555555)),
          ),
        ),
      ),
      if (!widget.replay)
        FadeIn(
          delay: 520,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 16, 26, 4),
            child: GestureDetector(
              onTap: () => widget.onSample(!widget.sample),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: C.black.withValues(alpha: .08)),
                ),
                child: Row(
                  children: [
                    const Text('📚', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Start with sample library',
                              style: TextStyle(fontFamily: F.sans, fontSize: 13.5, fontWeight: FontWeight.w600, color: C.black)),
                          Text('55 classic books ready to explore',
                              style: TextStyle(fontFamily: F.sans, fontSize: 12, color: Color(0xFF6B6B6B))),
                        ],
                      ),
                    ),
                    AppSwitch(value: widget.sample, onChanged: widget.onSample),
                  ],
                ),
              ),
            ),
          ),
        ),
      const SizedBox(height: 18),
      FadeIn(
        delay: 600,
        child: _Cta(
          widget.replay ? 'Change Google Account' : 'Continue with Google',
          leading: SvgPicture.string(googleLogoSvg, width: 22, height: 22),
          onTap: _openGoogleChooser,
        ),
      ),
    ]);
  }
}

class _Underline extends CustomPainter {
  final double t;
  _Underline(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final sx = size.width / 200, sy = size.height / 8;
    final p = Path()
      ..moveTo(2 * sx, 6 * sy)
      ..cubicTo(50 * sx, 1 * sy, 120 * sx, 1 * sy, 198 * sx, 4 * sy);
    final m = p.computeMetrics().first;
    canvas.drawPath(
      m.extractPath(0, m.length * t),
      Paint()
        ..color = C.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Underline o) => o.t != t;
}

// ---------------------------------------------------------------------------

class _GoogleStep extends StatefulWidget {
  final TextEditingController email;
  final bool replay, sample;
  final ValueChanged<bool> onSample;
  final VoidCallback onGo;
  const _GoogleStep({super.key, required this.email, required this.replay, required this.sample, required this.onSample, required this.onGo});
  @override
  State<_GoogleStep> createState() => _GoogleStepState();
}

class _GoogleStepState extends State<_GoogleStep> with TickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  void _go() {
    final em = widget.email.text.trim();
    if (em.isEmpty) {
      _openGoogleDialog();
    } else {
      widget.onGo();
    }
  }

  Future<void> _openGoogleDialog() async {
    try {
      final userCred = await AuthService.signInWithGoogle();
      if (userCred != null && userCred.user != null) {
        final email = userCred.user!.email ?? '';
        if (email.isNotEmpty) {
          widget.email.text = email;
          setState(() {});
          widget.onGo();
        }
      }
    } catch (e) {
      debugPrint('Google sign in error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    final rawEmail = widget.email.text.trim();
    final name = rawEmail.isNotEmpty ? AppStore.nameFromEmail(rawEmail) : '';
    final first = name.isNotEmpty ? name.split(RegExp(r'\s+')).first : '';

    return _Page(children: [
      FadeIn(
        child: SizedBox(
          height: 150,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedBuilder(
              animation: _bob,
              builder: (_, c) => Transform.translate(offset: Offset(-36, still ? 0 : sin(_bob.value * 2 * pi) * 5), child: c),
              child: SvgPicture.string(owlSvg, width: 120, height: 109),
            ),
            Positioned(
              right: MediaQuery.sizeOf(context).width / 2 - 150,
              top: 10,
              child: Transform.rotate(
                angle: 6 * pi / 180,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: springCurve,
                  builder: (_, v, c) => Transform.scale(scale: v, alignment: Alignment.bottomLeft, child: c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: C.black, width: 1.6),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        first.isEmpty ? 'Your shelf awaits!' : 'Hi, $first!',
                        key: ValueKey(first.isEmpty ? 'empty' : first),
                        style: const TextStyle(fontFamily: F.hand, fontWeight: FontWeight.w700, fontSize: 22, color: C.black),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(26, 18, 26, 0),
        child: FadeIn(
          delay: 120,
          child: Text(
            widget.replay ? 'Your Google Account' : 'Continue with\nGoogle',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: F.serif, fontWeight: FontWeight.w800, fontSize: 32, height: 1.1, letterSpacing: -.3, color: C.black),
          ),
        ),
      ),
      FadeIn(
        delay: 220,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(36, 14, 36, 0),
          child: Text(
            'Continue with your Google account to personalize your cozy bookshelves and reading to-dos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: F.sans, fontSize: 15, height: 1.45, color: Color(0xFF5D5D5D)),
          ),
        ),
      ),
      const SizedBox(height: 24),
      if (rawEmail.isNotEmpty)
        FadeIn(
          delay: 280,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.black.withValues(alpha: .14), width: 1.4),
                boxShadow: const [
                  BoxShadow(color: Color.fromRGBO(0, 0, 0, .04), offset: Offset(0, 2), blurRadius: 8),
                ],
              ),
              child: Row(children: [
                SvgPicture.string(googleLogoSvg, width: 24, height: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(fontFamily: F.sans, fontWeight: FontWeight.w700, fontSize: 15, color: C.black)),
                    Text(rawEmail, style: const TextStyle(fontFamily: F.sans, fontSize: 13, color: Color(0xFF6B6B6B))),
                  ]),
                ),
                TextButton(
                  onPressed: _openGoogleDialog,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Change', style: TextStyle(fontFamily: F.sans, fontWeight: FontWeight.w600, fontSize: 13, color: C.orange)),
                ),
              ]),
            ),
          ),
        ),
      if (rawEmail.isNotEmpty) const SizedBox(height: 8),
      if (!widget.replay)
        FadeIn(
          delay: 360,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 2, 26, 8),
            child: GestureDetector(
              onTap: () => widget.onSample(!widget.sample),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x1F000000)),
                ),
                child: Row(children: [
                  const Text('📚', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Start with a sample library',
                          style: TextStyle(fontFamily: F.sans, fontSize: 15, fontWeight: FontWeight.w500, color: C.black)),
                      SizedBox(height: 2),
                      Text('55 well-loved books and a few to-dos to play with. Remove them anytime.',
                          style: TextStyle(fontFamily: F.sans, fontSize: 12.5, height: 1.35, color: Color(0xFF6B6B6B))),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  AppSwitch(value: widget.sample, onChanged: widget.onSample),
                ]),
              ),
            ),
          ),
        ),
      const SizedBox(height: 18),
      FadeIn(
        delay: 440,
        child: _Cta(
          rawEmail.isNotEmpty ? 'Continue as $first' : 'Continue with Google',
          leading: SvgPicture.string(googleLogoSvg, width: 22, height: 22),
          onTap: _go,
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------

class _NotifyStep extends StatefulWidget {
  final VoidCallback onDone;
  const _NotifyStep({super.key, required this.onDone});
  @override
  State<_NotifyStep> createState() => _NotifyStepState();
}

class _NotifyStepState extends State<_NotifyStep> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  String _label = 'Turn on notifications';
  bool _busy = false;

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  Future<void> _on() async {
    if (_busy) return;
    _busy = true;
    final ok = await Notifier.requestPermission();
    store.settings.reminders = ok;
    store.changed();
    setState(() => _label = ok ? 'You’re all set' : 'Maybe next time');
    Sfx.play(ok ? 'check' : 'tap');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final still = mq.disableAnimations;
    const sizes = [58.0, 56.0, 74.0, 58.0, 70.0, 56.0];
    const tops = [0.0, 20.0, -14.0, 4.0, 24.0, -6.0];
    return _Page(children: [
      SizedBox(
        height: 110,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          OverflowBox(
            maxWidth: double.infinity,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 6; i++)
                Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                  child: AnimatedBuilder(
                    animation: _bob,
                    builder: (_, c) => Transform.translate(
                      offset: Offset(0, tops[i] + (still ? 0 : sin((_bob.value + i * .17) * 2 * pi) * 3)),
                      child: c,
                    ),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 550 + i * 90),
                      curve: Interval(i * 90 / (550 + i * 90), 1, curve: springCurve),
                      builder: (_, v, c) => Transform.scale(scale: v, child: c),
                      child: ClipOval(child: SvgPicture.string(introAvatars[i], width: sizes[i], height: sizes[i])),
                    ),
                  ),
                ),
            ]),
          ),
          Positioned(left: mq.size.width / 2 - 120, top: 2, child: const _Tick(left: true)),
          Positioned(left: mq.size.width / 2 + 56, top: 2, child: const _Tick(left: false)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 0),
        child: FadeIn(
          delay: 200,
          child: Text('Never lose track\nof your next read.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: F.serif, fontWeight: FontWeight.w800, fontSize: mq.size.width <= 360 ? 25 : 29, height: 1.12, letterSpacing: -.3, color: C.black)),
        ),
      ),
      FadeIn(
        delay: 320,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(40, 16, 40, 0),
          child: Text('Get a gentle reminder when a to-do is due, plus rewards when you hit reading milestones.',
              textAlign: TextAlign.center, style: TextStyle(fontFamily: F.sans, fontSize: 16, height: 1.5, color: Color(0xFF5D5D5D))),
        ),
      ),
      const SizedBox(height: 26),
      FadeIn(
        delay: 440,
        child: _Cta(_label,
            onTap: _on,
            trailing: CustomPaint(size: const Size(20, 20), painter: _Lines())),
      ),
      const SizedBox(height: 22),
      FadeIn(
        delay: 540,
        child: Center(
          child: TextButton(
            onPressed: () {
              Buzz.tick();
              widget.onDone();
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF6B6B6B), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
            child: const Text('Maybe later', style: TextStyle(fontFamily: F.sans, fontSize: 16)),
          ),
        ),
      ),
    ]);
  }
}

class _Tick extends StatelessWidget {
  final bool left;
  const _Tick({required this.left});
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(22, 22), painter: _TickPainter(left));
}

class _TickPainter extends CustomPainter {
  final bool left;
  _TickPainter(this.left);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = C.orange
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (left) {
      c.drawLine(const Offset(4, 2), const Offset(1, 10), p);
      c.drawLine(const Offset(12, 0), const Offset(14, 8), p);
    } else {
      c.drawLine(const Offset(2, 0), const Offset(5, 8), p);
      c.drawLine(const Offset(13, 4), const Offset(11, 10), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _Lines extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = C.orange
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    c.drawLine(const Offset(3, 4), const Offset(9, 8), p);
    c.drawLine(const Offset(3, 10), const Offset(10, 10), p);
    c.drawLine(const Offset(3, 16), const Offset(9, 12), p);
  }

  @override
  bool shouldRepaint(_) => false;
}
