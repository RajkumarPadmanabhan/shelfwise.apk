import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'data/store.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Applies the chosen theme, accent and font, and repaints the app when they change.
class Look {
  static final sig = ValueNotifier<String>('');

  static bool get wantsDark {
    final s = store.settings;
    final platform = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return s.theme == 'dark' || (s.theme == 'system' && platform == Brightness.dark);
  }

  static void apply({bool animate = false}) {
    final s = store.settings;
    final dark = wantsDark;
    final next = '$dark|${s.accent}|${s.font}|${s.textScale}|${s.bg}|${s.pattern}';
    if (next == sig.value) return;
    final first = sig.value.isEmpty;
    C.p = palFor(s.bg, dark);
    C.accent = accents[s.accent.clamp(0, accents.length - 1)].color;
    F.ui = fontChoices.any((f) => f.$1 == s.font) ? s.font : F.nunito;
    overlay();
    sig.value = next;
    if (first) return;
    if (animate) Fx.add(_Fade(color: C.bg), 520);
    _rebuildAll();
  }

  /// Status/navigation bar icons that suit the current background.
  static void overlay({bool forceDarkIcons = false}) {
    final light = forceDarkIcons || !C.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      statusBarBrightness: light ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
    ));
  }

  static void _rebuildAll() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void build(Element e) {
      e.markNeedsBuild();
      e.visitChildren(build);
    }

    build(root);
    void paint(RenderObject r) {
      r.markNeedsPaint();
      r.visitChildren(paint);
    }

    for (final v in RendererBinding.instance.renderViews) {
      paint(v);
    }
  }
}

class _Fade extends StatelessWidget {
  final Color color;
  const _Fade({required this.color});
  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1, end: 0),
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeOut,
          builder: (_, v, _) => ColoredBox(color: color.withValues(alpha: v)),
        ),
      );
}
