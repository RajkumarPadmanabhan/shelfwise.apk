import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/common.dart';
import 'library_screen.dart';

/// Every shelf at once on a dark wooden wall (the mockup's full-screen shelf).
void openFullShelf() {
  Sfx.play('swoosh');
  dropFocus();
  navKey.currentState!.push(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => const _FullShelf(),
    transitionsBuilder: (_, a, _, child) {
      final t = CurvedAnimation(parent: a, curve: ease);
      return FadeTransition(
        opacity: t,
        child: SlideTransition(position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(t), child: child),
      );
    },
  ));
}

class _FullShelf extends StatelessWidget {
  const _FullShelf();

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // light theme: a warm cream wall with wooden shelves; dark theme: the mockup's dark wood
    final dark = C.dark;
    final wall = dark ? const Color(0xFF2B1D10) : const Color(0xFFF1E3CB);
    final ink = dark ? const Color(0xFFF3EEE6) : C.ink;
    final soft = dark ? const Color(0xFFCDBFAE) : C.muted;
    final nook = dark
        ? const [Color.fromRGBO(255, 255, 255, .03), Color.fromRGBO(255, 255, 255, .09)]
        : const [Color.fromRGBO(120, 75, 30, .05), Color.fromRGBO(120, 75, 30, .13)];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
      backgroundColor: wall,
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final total = store.totalBooks;
          return Column(children: [
            Container(
              padding: EdgeInsets.fromLTRB(16, mq.padding.top + 14, 16, 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: dark ? const Color.fromRGBO(255, 255, 255, .12) : C.line))),
              child: Row(children: [
                Expanded(
                  child: Text('📚 ${store.profile.first}’s shelf',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(18, FontWeight.w800, ink)),
                ),
                Text(plural(total, 'book'), style: nu(12, FontWeight.w700, soft)),
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: 'Close full screen',
                  child: Pressable(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: dark ? const Color.fromRGBO(255, 255, 255, .14) : C.chip, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Icon(Icons.close_rounded, color: ink, size: 18),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: store.cols.isEmpty
                  ? Center(child: Text('No books on this shelf yet.', style: nu(15, FontWeight.w600, soft)))
                  : ListView(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + mq.padding.bottom),
                      children: [
                        for (final (i, c) in store.cols.indexed)
                          FadeIn(
                            delay: i * 70,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
                                child: Row(children: [
                                  Expanded(child: Text('${c.emoji} ${c.name}', style: nu(16, FontWeight.w800, ink))),
                                  Text(plural(c.books.length, 'book'), style: nu(12, FontWeight.w700, soft)),
                                ]),
                              ),
                              Container(
                                padding: const EdgeInsets.fromLTRB(10, 22, 10, 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
                                  border: Border(bottom: BorderSide(color: dark ? C.plank : const Color(0xFFA9834F), width: 8)),
                                  boxShadow: dark ? null : const [BoxShadow(color: Color.fromRGBO(90, 55, 20, .22), offset: Offset(0, 6), blurRadius: 8, spreadRadius: -4)],
                                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: nook),
                                ),
                                child: c.items.isEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Text('Empty shelf', textAlign: TextAlign.center, style: nu(13, FontWeight.w700, soft)),
                                      )
                                    : Wrap(
                                        spacing: 10,
                                        runSpacing: 12,
                                        crossAxisAlignment: WrapCrossAlignment.end,
                                        children: [
                                          for (final it in c.items)
                                            Pressable(
                                              onTap: () => it.isDecor ? openDecor(c, it, home: true) : openBookView(c, it),
                                              child: it.isDecor
                                                  ? (it.gadget == 'cd'
                                                      ? GadgetView(it.gadget!, w: 112 * .8, h: 112 * .8, lit: it.lit)
                                                      : GadgetView(it.gadget!, w: 78 * .85, h: 112 * gadgetHeightFactor(it.gadget!), lit: it.lit))
                                                  : DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        borderRadius: BorderRadius.circular(5),
                                                        boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .4), offset: Offset(0, 2), blurRadius: 6)],
                                                      ),
                                                      child: BookCover(it, w: 78, h: 112),
                                                    ),
                                            ),
                                        ],
                                      ),
                              ),
                            ]),
                          ),
                      ],
                    ),
            ),
          ]);
        },
      ),
    ),
    );
  }
}
