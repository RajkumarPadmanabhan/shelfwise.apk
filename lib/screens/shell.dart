import 'package:flutter/material.dart';

import '../data/store.dart';
import '../icons.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pet_overlay.dart';
import 'library_screen.dart';
import 'onboarding.dart';
import 'posts_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'todo_screen.dart';

/// Main app frame: one page at a time plus the frosted bottom nav.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0; // 0 home, 1 library, 2 to-do, 3 stats, 4 settings, 5 profile, 6 explore

  void go(int t) {
    dropFocus();
    if (t == 0) {
      LibUi.f = 'all';
      LibUi.q = '';
      LibUi.exp = false;
    }
    setState(() => _tab = t);
  }


  Widget _page() => switch (_tab) {
        0 => LibraryScreen(key: const ValueKey('home'), home: true, onProfile: () => go(5), onTodo: () => go(2), onStats: () => go(3)),
        1 => LibraryScreen(key: const ValueKey('lib'), home: false, onProfile: () => go(5), onTodo: () => go(2), onStats: () => go(3)),
        6 => const PostsScreen(key: ValueKey('explore')),
        2 => const TodoScreen(key: ValueKey('todo')),
        3 => const StatsScreen(key: ValueKey('stats')),
        4 => SettingsScreen(key: const ValueKey('settings'), onProfile: () => go(5), onReplay: () => Navigator.of(context).push(introRoute())),
        _ => ProfileScreen(key: const ValueKey('profile'), go: go),
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) go(0);
      },
      child: Scaffold(
        backgroundColor: C.bg,
        resizeToAvoidBottomInset: false,
        body: Stack(children: [
          if (store.settings.pattern != 'none')
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: PatternPainter(store.settings.pattern, C.ink.withValues(alpha: C.dark ? .07 : .06))),
                ),
              ),
            ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: ease,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, .018), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: _page(),
            ),
          ),
          if (_tab == 0)
            const Positioned.fill(
              child: PetOverlay(tab: 0),
            ),
          Positioned(left: 0, right: 0, top: 0, height: MediaQuery.paddingOf(context).top, child: ColoredBox(color: C.bg.withValues(alpha: .95))),
          Positioned(left: 0, right: 0, bottom: 0, child: _NavBar(tab: _tab, onTab: go)),
        ]),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTab;
  const _NavBar({required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: blur(10),
        child: Container(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 12 + bottom),
          decoration: BoxDecoration(
            color: C.nav,
            border: Border(top: BorderSide(color: Color(0x0D000000))),
          ),
          child: ListenableBuilder(
            listenable: store,
            builder: (_, _) => Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _HomeLibToggleBtn(tab: tab, onTab: onTab),
              _NavBtn(Ic.explore, 'Explore', tab == 6, () => onTab(6)),
              _NavBtn(Ic.todo, 'To-do', tab == 2, () => onTab(2), dot: store.dueTodos.isNotEmpty),
              _NavBtn(Ic.stats, 'Stats', tab == 3, () => onTab(3)),
              _NavBtn(Ic.settings, 'Settings', tab == 4 || tab == 5, () => onTab(4)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _HomeLibToggleBtn extends StatefulWidget {
  final int tab;
  final ValueChanged<int> onTab;
  const _HomeLibToggleBtn({required this.tab, required this.onTab});

  @override
  State<_HomeLibToggleBtn> createState() => _HomeLibToggleBtnState();
}

class _HomeLibToggleBtnState extends State<_HomeLibToggleBtn> {
  bool _down = false;
  bool _libMode = false;

  @override
  void didUpdateWidget(_HomeLibToggleBtn old) {
    super.didUpdateWidget(old);
    if (widget.tab == 1 && !_libMode) {
      _libMode = true;
    } else if (widget.tab == 0 && _libMode) {
      _libMode = false;
    }
  }

  void _toggle() {
    Buzz.medium();
    Sfx.play('tap');
    if (_libMode || widget.tab == 1) {
      setState(() => _libMode = false);
      widget.onTab(0);
      toast('Home · Double-tap for Library');
    } else {
      setState(() => _libMode = true);
      widget.onTab(1);
      toast('Library · Double-tap for Home');
    }
  }

  void _onSingleTap() {
    Buzz.tick();
    if (widget.tab != 0 && widget.tab != 1) {
      widget.onTab(_libMode ? 1 : 0);
    } else {
      if (widget.tab == 0) {
        toast('Double-tap Home to open Library');
      } else {
        toast('Double-tap Library to open Home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLib = (widget.tab == 1) || (_libMode && widget.tab != 0);
    final on = widget.tab == 0 || widget.tab == 1;
    final color = on ? C.brown : C.ink;
    final icon = isLib ? Ic.library : Ic.home;
    final label = isLib ? 'Library' : 'Home';

    return Semantics(
      button: true,
      selected: on,
      label: '$label (Double-tap to switch)',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: _onSingleTap,
        onDoubleTap: _toggle,
        child: AnimatedScale(
          scale: _down ? .92 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: ease,
            width: 68,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: on ? const Color.fromRGBO(184, 105, 42, .14) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, anim) => RotationTransition(
                    turns: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
                    child: FadeTransition(opacity: anim, child: ScaleTransition(scale: anim, child: child)),
                  ),
                  child: SvgIcon(
                    icon,
                    key: ValueKey(icon),
                    color: color,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 1),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    label,
                    key: ValueKey(label),
                    style: nu(11, on ? FontWeight.w800 : FontWeight.w600, color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _NavBtn extends StatefulWidget {
  final String icon, label;
  final bool on, dot;
  final VoidCallback onTap;
  const _NavBtn(this.icon, this.label, this.on, this.onTap, {this.dot = false});
  @override
  State<_NavBtn> createState() => _NavBtnState();
}

class _NavBtnState extends State<_NavBtn> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.on ? C.brown : C.ink;
    return Semantics(
      button: true,
      selected: widget.on,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          Buzz.tick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? .92 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: ease,
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: widget.on ? const Color.fromRGBO(184, 105, 42, .14) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(clipBehavior: Clip.none, children: [
                TweenAnimationBuilder<double>(
                  key: ValueKey(widget.on),
                  tween: Tween(begin: widget.on ? .8 : 1, end: 1),
                  duration: const Duration(milliseconds: 380),
                  curve: popCurve,
                  builder: (_, s, c) => Transform.scale(scale: s, child: c),
                  child: SvgIcon(widget.icon, color: color, size: 26),
                ),
                if (widget.dot)
                  Positioned(
                    top: -3,
                    right: -5,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4F0F),
                        shape: BoxShape.circle,
                        border: Border.all(color: C.bg, width: 2),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 2),
              Text(widget.label, style: nu(11, FontWeight.w700, color)),
            ]),
          ),
        ),
      ),
    );
  }
}
