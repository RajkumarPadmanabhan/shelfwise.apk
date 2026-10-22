import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// A dialog action. [onTap] returning false keeps the dialog open (validation);
/// [then] runs after the dialog has closed (e.g. to open the next dialog).
class Btn {
  final String? label;
  final Widget? icon;
  final String? tip;
  final Kind kind;
  final FutureOr<bool?> Function()? onTap;
  final VoidCallback? then;
  final bool breakBefore;
  final bool small;
  const Btn(this.label,
      {this.icon, this.tip, this.kind = Kind.normal, this.onTap, this.then, this.breakBefore = false, this.small = false});
  const Btn.icon(Widget this.icon,
      {required this.tip, this.kind = Kind.normal, this.onTap, this.then, this.breakBefore = false})
      : label = null,
        small = false;
}

Future<T?> openDialog<T>(Widget Function(BuildContext ctx) builder, {bool dismissible = true}) {
  final ctx = navKey.currentContext!;
  dropFocus();
  return showGeneralDialog<T>(
    context: ctx,
    barrierDismissible: dismissible,
    barrierLabel: 'Close',
    barrierColor: const Color.fromRGBO(40, 25, 10, .45),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (c, _, _) => builder(c),
    transitionBuilder: (c, a, _, child) {
      final t = CurvedAnimation(parent: a, curve: ease, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: t,
        child: ScaleTransition(scale: Tween(begin: .94, end: 1.0).animate(t), child: child),
      );
    },
  );
}

/// The cream dialog card (`dialog#dlg`, `#xd`).
class AppDialog extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final List<Btn> actions;
  final double maxWidth;
  final bool centerActions;
  final EdgeInsets pad;
  final Clip clip;
  const AppDialog(
      {super.key,
      this.title,
      this.children = const [],
      this.actions = const [],
      this.maxWidth = 360,
      this.centerActions = false,
      this.pad = const EdgeInsets.all(22),
      this.clip = Clip.antiAlias});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = (mq.size.width - 32).clamp(0.0, maxWidth);
    final hasIcons = actions.any((b) => b.icon != null && b.label == null);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Center(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: w,
            constraints: BoxConstraints(maxHeight: mq.size.height - mq.viewInsets.bottom - 32 - mq.padding.vertical),
            clipBehavior: clip,
            decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(22)),
            child: SingleChildScrollView(
              padding: pad,
              clipBehavior: clip == Clip.none ? Clip.none : Clip.hardEdge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(title!, style: nu(20, FontWeight.w800, C.ink, 1.25)),
                    ),
                  ...children,
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _Actions(actions, center: centerActions || hasIcons),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final List<Btn> btns;
  final bool center;
  const _Actions(this.btns, {required this.center});

  Future<void> _run(BuildContext context, Btn b) async {
    final r = b.onTap == null ? null : await b.onTap!();
    if (r == false || !context.mounted) return;
    Navigator.of(context).pop();
    b.then?.call();
  }

  @override
  Widget build(BuildContext context) {
    final rows = <List<Btn>>[[]];
    for (final b in btns) {
      if (b.breakBefore && rows.last.isNotEmpty) rows.add([]);
      rows.last.add(b);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in rows.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Wrap(
              alignment: center ? WrapAlignment.center : WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in row)
                  b.label == null
                      ? _IconAction(b, () => _run(context, b))
                      : Pill(b.label!,
                          kind: b.kind,
                          icon: b.icon,
                          size: b.small || i > 0 && rows.length > 1 && center ? 13 : 14,
                          pad: b.small || i > 0 && rows.length > 1 && center
                              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
                              : const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                          onTap: () => _run(context, b)),
              ],
            ),
          ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  final Btn b;
  final VoidCallback onTap;
  const _IconAction(this.b, this.onTap);

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (b.kind) {
      Kind.pri => (C.brown, Colors.white),
      Kind.dng => (C.dangerBg, C.dangerInk),
      _ => (C.chip, C.ink),
    };
    return Tooltip(
      message: b.tip ?? '',
      child: Semantics(
        button: true,
        label: b.tip,
        child: Pressable(
          onTap: onTap,
          scale: .9,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: IconTheme(data: IconThemeData(color: fg), child: DefaultTextStyle(style: TextStyle(color: fg), child: b.icon!)),
          ),
        ),
      ),
    );
  }
}

/// Muted paragraph (`dialog p`).
class Sub extends StatelessWidget {
  final String text;
  final double size;
  final EdgeInsets pad;
  const Sub(this.text, {super.key, this.size = 14, this.pad = const EdgeInsets.only(bottom: 10)});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: pad, child: Text(text, style: nu(size, FontWeight.w600, C.muted, 1.4)));
}

class ErrText extends StatelessWidget {
  final String text;
  const ErrText(this.text, {super.key});
  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: const Duration(milliseconds: 160),
        child: text.isEmpty
            ? const SizedBox(height: 4, width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(text, style: nu(13, FontWeight.w700, C.error)),
              ),
      );
}

/// Simple yes/no confirmation.
Future<bool> confirm(String title, String body, {String yes = 'Remove', String no = 'Keep it', Kind kind = Kind.dng}) async {
  var ok = false;
  await openDialog((_) => AppDialog(title: title, children: [Sub(body)], actions: [
        Btn(no),
        Btn(yes, kind: kind, onTap: () => ok = true),
      ]));
  return ok;
}
