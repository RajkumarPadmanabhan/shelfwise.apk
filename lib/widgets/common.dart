import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../art.dart';
import '../data/store.dart';
import '../icons.dart';
import '../services/sfx.dart';
import '../theme.dart';

final navKey = GlobalKey<NavigatorState>();

/// Closes the keyboard so it doesn't pop back up when a dialog or page closes.
void dropFocus() => FocusManager.instance.primaryFocus?.unfocus();

// ---------------------------------------------------------------------------
// Global effects layer: toast + anything that must float above every route.
// ---------------------------------------------------------------------------

class Fx {
  static final toastMsg = ValueNotifier<String?>(null);
  static final layers = ValueNotifier<List<Widget>>(const []);
  static Timer? _t;

  static void toast(String m) {
    toastMsg.value = m;
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 1900), () => toastMsg.value = null);
  }

  /// Shows [w] above everything until [ms] passes.
  static void add(Widget w, int ms) {
    final k = UniqueKey();
    final keyed = KeyedSubtree(key: k, child: w);
    layers.value = [...layers.value, keyed];
    Timer(Duration(milliseconds: ms), () => layers.value = layers.value.where((e) => e.key != k).toList());
  }
}

void toast(String m) => Fx.toast(m);

class FxHost extends StatelessWidget {
  final Widget child;
  const FxHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    // The toast and effects layers sit above the Navigator, outside any Material,
    // so give them a real text style (otherwise Flutter draws its yellow double underline).
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: nu(14, FontWeight.w600),
        child: _layers(bottom, context),
      ),
    );
  }

  Widget _layers(double bottom, BuildContext context) {
    return Stack(children: [
      child,
      Positioned.fill(
        child: IgnorePointer(
          child: ValueListenableBuilder<List<Widget>>(
            valueListenable: Fx.layers,
            builder: (_, l, _) => Stack(clipBehavior: Clip.none, children: l),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 104 + bottom,
        child: IgnorePointer(
          child: ValueListenableBuilder<String?>(
            valueListenable: Fx.toastMsg,
            builder: (_, m, _) => AnimatedOpacity(
              opacity: m == null ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .86),
                  child: _ToastPill(m),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _ToastPill extends StatefulWidget {
  final String? m;
  const _ToastPill(this.m);
  @override
  State<_ToastPill> createState() => _ToastPillState();
}

class _ToastPillState extends State<_ToastPill> {
  String _last = '';
  @override
  Widget build(BuildContext context) {
    if (widget.m != null) _last = widget.m!;
    if (_last.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: C.toast, borderRadius: BorderRadius.circular(20)),
      child: Text(_last, textAlign: TextAlign.center, style: nu(14, FontWeight.w600, Colors.white)),
    );
  }
}

// ---------------------------------------------------------------------------
// Small building blocks
// ---------------------------------------------------------------------------

/// Shrinks a touch on press, like the mockup's :active scale.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final String? sound;
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = .95, this.sound});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onLongPress: widget.onLongPress,
      onTap: widget.onTap == null
          ? null
          : () {
              Buzz.tick();
              if (widget.sound != null) Sfx.play(widget.sound!);
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

enum Kind { normal, pri, dng, outline, ghost }

/// Rounded pill button (`.ma button`, `.btn`, `.sm`).
class Pill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Kind kind;
  final double size;
  final EdgeInsets pad;
  final bool expand;
  final Widget? icon;
  const Pill(this.label,
      {super.key,
      this.onTap,
      this.kind = Kind.normal,
      this.size = 14,
      this.pad = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      this.expand = false,
      this.icon});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (kind) {
      Kind.pri => (C.brown, Colors.white),
      Kind.dng => (C.dangerBg, C.dangerInk),
      Kind.outline => (Colors.transparent, C.brown),
      Kind.ghost => (Colors.transparent, C.chipText),
      Kind.normal => (C.chip, C.ink),
    };
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: pad,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          border: kind == Kind.outline ? Border.all(color: C.brown, width: 1.5) : null,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 6)],
            Flexible(
              child: Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nu(size, FontWeight.w700, fg)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 48x28 toggle (`.sw`).
class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const AppSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: () {
          Buzz.tick();
          onChanged(!value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: value ? C.brown : C.switchOff, borderRadius: BorderRadius.circular(14)),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filter chip with the mockup's `chipPop` spring when it becomes selected.
class PopChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool dashed;
  final double fontSize;
  final EdgeInsets pad;
  final Color? onColor;
  final Color? onText;
  const PopChip(this.label,
      {super.key,
      required this.on,
      required this.onTap,
      this.onLongPress,
      this.dashed = false,
      this.fontSize = 15,
      this.pad = const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      this.onColor,
      this.onText});

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: pad,
      decoration: BoxDecoration(
        color: dashed ? Colors.transparent : (on ? (onColor ?? C.brown) : C.chip),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: nu(fontSize, FontWeight.w700, dashed ? C.brown : (on ? (onText ?? Colors.white) : C.chipText))),
    );
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: .94,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(on),
        tween: Tween(begin: on ? .86 : 1, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: popCurve,
        builder: (_, s, c) => Transform.scale(scale: s, child: c),
        child: dashed ? CustomPaint(painter: _DashPainter(), child: chip) : chip,
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)).deflate(.75);
    final path = Path()..addRRect(r);
    final p = Paint()
      ..color = C.brown
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 4), p);
      }
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

/// Text field in the mockup's dialog style.
class AppInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final int lines;
  final bool autofocus;
  final TextInputType? type;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization caps;
  const AppInput(this.controller, this.hint,
      {super.key,
      this.maxLength = 60,
      this.lines = 1,
      this.autofocus = false,
      this.type,
      this.onChanged,
      this.onSubmitted,
      this.caps = TextCapitalization.sentences});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        maxLength: maxLength,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 3,
        keyboardType: type,
        textCapitalization: caps,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: nu(16, FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: nu(16, FontWeight.w600, C.hint),
          counterText: '',
          isDense: true,
          filled: true,
          fillColor: C.field,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: C.inputLine)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: C.brown, width: 2)),
        ),
      ),
    );
  }
}

/// Round 42px header button with an optional badge (`.gift`, `.bellx`).
class BadgeButton extends StatelessWidget {
  final String icon;
  final int count;
  final VoidCallback onTap;
  final String label;
  final double size;
  const BadgeButton({super.key, required this.icon, required this.count, required this.onTap, required this.label, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: count > 0 ? '$label, $count' : label,
      child: Pressable(
        onTap: onTap,
        scale: .9,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: C.softBrown, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: SvgIcon(icon, color: C.dark ? C.chipText : const Color(0xFF6D4A2B), size: 22),
            ),
            if (count > 0)
              Positioned(
                top: -4,
                right: -4,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(count),
                  tween: Tween(begin: .4, end: 1),
                  duration: const Duration(milliseconds: 420),
                  curve: popCurve,
                  builder: (_, s, c) => Transform.scale(scale: s, child: c),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: C.brown, borderRadius: BorderRadius.circular(9)),
                    alignment: Alignment.center,
                    child: Text('$count', style: nu(10, FontWeight.w700, Colors.white)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// The owl mascot, or the user's photo when they've set one.
class MeAvatar extends StatelessWidget {
  final double size;
  final bool border;
  const MeAvatar({super.key, this.size = 52, this.border = false});

  @override
  Widget build(BuildContext context) {
    final p = store.profile.photo;
    if (p != null && store.imageFile(p).existsSync()) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: C.chip,
          border: border ? Border.all(color: C.bg, width: 4) : null,
          image: DecorationImage(image: FileImage(store.imageFile(p)), fit: BoxFit.cover),
        ),
      );
    }
    return SvgPicture.string(owlSvg, width: size, height: size * 58 / 64);
  }
}

/// Section heading (`h2`).
class H2 extends StatelessWidget {
  final String text;
  final EdgeInsets pad;
  const H2(this.text, {super.key, this.pad = const EdgeInsets.fromLTRB(0, 26, 0, 10)});
  @override
  Widget build(BuildContext context) => Padding(padding: pad, child: Text(text, style: nu(17, FontWeight.w800)));
}

/// Page title (`h1`), clamped like the mockup.
class H1 extends StatelessWidget {
  final String text;
  const H1(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Text(text, style: nu((w * .074).clamp(24.0, 30.0), FontWeight.w800, C.ink, 1.1).copyWith(letterSpacing: -.3));
  }
}

/// White card with hairline border (`.card`, `.cc`, `.tile`).
class CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets pad;
  final double radius;
  const CardBox({super.key, required this.child, this.pad = const EdgeInsets.all(14), this.radius = 18});
  @override
  Widget build(BuildContext context) => Container(
        padding: pad,
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: C.line),
        ),
        child: child,
      );
}

/// Fades + lifts its child in once (used for list entrances).
class FadeIn extends StatelessWidget {
  final Widget child;
  final int delay;
  final double dy;
  final int ms;
  const FadeIn({super.key, required this.child, this.delay = 0, this.dy = 14, this.ms = 450});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms + delay),
      curve: Interval(delay / (ms + delay), 1, curve: ease),
      builder: (_, t, c) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, dy * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

String fmtDue(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final label = switch (diff) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => '${mon[d.month - 1]} ${d.day}',
  };
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$label · $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// 3725 → "1h 2m", 300 → "5 min".
String fmtDuration(int seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '${h}h' : '${h}h ${r}m';
}

String fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return d.year == DateTime.now().year ? '${mon[d.month - 1]} ${d.day}' : '${mon[d.month - 1]} ${d.day}, ${d.year}';
}
