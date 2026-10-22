import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../art.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'book_share_sheet.dart';
import 'common.dart';
import 'dialogs.dart';
import 'pet_overlay.dart';
import 'shelf_cd.dart';
import 'sticky_note.dart';

class _Slot {
  final Item it;
  final double x, w, h;
  _Slot(this.it, this.x, this.w, this.h);
  double get mid => x + w / 2;
}

/// One shelf: overlapping books on a pastel glass band, with label, actions and slider.
class ShelfRow extends StatefulWidget {
  final Collection col;
  final int palette;
  final List<Item> items;
  final bool sub, home, exp, filtered;
  final int count;
  final void Function(Item it) onOpen;
  final VoidCallback? onMore, onAdd, onDecor;
  const ShelfRow({
    super.key,
    required this.col,
    required this.palette,
    required this.items,
    required this.count,
    required this.onOpen,
    this.sub = false,
    this.home = false,
    this.exp = false,
    this.filtered = false,
    this.onMore,
    this.onAdd,
    this.onDecor,
  });

  @override
  State<ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends State<ShelfRow> with TickerProviderStateMixin {
  final _sc = ScrollController();
  final _stackKey = GlobalKey();
  final _viewKey = GlobalKey();
  final _boxKey = GlobalKey();
  late final AnimationController _shine =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final Ticker _auto = createTicker(_autoScroll);

  String? _pressed;
  Item? _drag;
  double _dragX = 0, _dragY = 0, _grab = 0, _finger = 0, _vx = 0;
  int? _insertAt; // where the dragged item would land; the others slide apart to make room
  bool _overflow = false;
  final Set<String> _fresh = {};

  double get _w => (MediaQuery.sizeOf(context).width * .21).clamp(70.0, 88.0);
  double get _h => _w * 1.42;
  bool get _canDrag => !widget.exp;

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.home) {
      final key = '${widget.col.id}-${widget.sub ? "sub" : "main"}';
      ShelfBoundsRegistry.register(key, _boxKey);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOverflow();
      _reportBounds();
    });
  }

  @override
  void didUpdateWidget(ShelfRow old) {
    super.didUpdateWidget(old);
    final before = old.items.map((e) => e.id).toSet();
    for (final it in widget.items) {
      if (!before.contains(it.id)) _fresh.add(it.id);
    }
    if (widget.home) {
      final key = '${widget.col.id}-${widget.sub ? "sub" : "main"}';
      ShelfBoundsRegistry.register(key, _boxKey);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOverflow();
      _reportBounds();
    });
  }

  @override
  void dispose() {
    if (widget.home) {
      final key = '${widget.col.id}-${widget.sub ? "sub" : "main"}';
      ShelfBoundsRegistry.unregister(key);
    }
    _auto.dispose();
    _shine.dispose();
    _sc.dispose();
    super.dispose();
  }

  void _reportBounds() {
    if (!mounted || !widget.home) return;
    final ro = _boxKey.currentContext?.findRenderObject() as RenderBox? ??
        context.findRenderObject() as RenderBox?;
    if (ro != null && ro.hasSize) {
      final pos = ro.localToGlobal(Offset.zero);
      final key = '${widget.col.id}-${widget.sub ? "sub" : "main"}';
      ShelfBoundsRegistry.homeShelves[key] = Rect.fromLTWH(pos.dx, pos.dy, ro.size.width, ro.size.height);
    }
  }

  void _checkOverflow() {
    if (!mounted || !_sc.hasClients) return;
    final o = _sc.position.maxScrollExtent > 4;
    if (o != _overflow) setState(() => _overflow = o);
  }

  /// The items in display order: while dragging, the dragged one sits at [_insertAt].
  List<Item> get _ordered {
    final d = _drag, at = _insertAt;
    if (d == null || at == null) return widget.items;
    final others = widget.items.where((x) => x.id != d.id).toList();
    return others..insert(at.clamp(0, others.length), d);
  }

  (List<_Slot>, double) _layout([List<Item>? items]) {
    final w = _w, h = _h;
    final out = <_Slot>[];
    var x = 22.0, prevMr = 0.0;
    for (final (i, it) in (items ?? _ordered).indexed) {
      final g = it.isDecor;
      final isCd = it.gadget == 'cd';
      // decorations stand behind the glass like the books, drawn tall enough to peek over it
      final double iw;
      final double ih;
      if (isCd) {
        ih = h * .8;
        iw = ih; // square, so the disc stays round
      } else {
        iw = g ? w * .95 : w;
        ih = g ? h * shelfGadgetFactor(it.gadget!) : h;
      }
      final double ml;
      if (i == 0) {
        ml = 0.0;
      } else if (isCd) {
        ml = -ih * 0.34; // ~34% hidden behind the previous book
      } else {
        ml = g ? -w * .05 : -w * .32;
      }
      x += prevMr + ml;
      out.add(_Slot(it, x, iw, ih));
      x += iw;
      prevMr = isCd ? (w * .1) : (g ? w * .28 : 0);
    }
    return (out, x + prevMr + 30);
  }

  // ---------------- press & drag ----------------

  void _tapDown(Item it) {
    if (_drag != null) return;
    setState(() => _pressed = it.id);
    if (!it.isDecor) _shine.forward(from: 0);
  }

  void _tapUp(Item it) {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _pressed = null);
      widget.onOpen(it);
    });
  }

  void _dragStart(Item it, _Slot s, LongPressStartDetails d) {
    if (widget.home && it.isDecor) return;
    Buzz.medium();
    Sfx.play('lift');
    setState(() {
      _pressed = null;
      _drag = it;
      _grab = d.localPosition.dx;
      _dragX = s.x;
      _dragY = 0;
      _finger = s.x + _grab;
      _insertAt = widget.items.indexOf(it);
    });
    if (!widget.home) _auto.start();
  }

  void _dragMove(LongPressMoveUpdateDetails d) {
    if (widget.home) {
      final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final local = box.globalToLocal(d.globalPosition);
        final dy = local.dy - (_h * 0.7);
        setState(() {
          _dragX = local.dx - _grab;
          _dragY = dy.clamp(-220.0, 20.0);
        });
      }
      return;
    }
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final view = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || view == null) return;
    _finger = box.globalToLocal(d.globalPosition).dx;
    final vx = view.globalToLocal(d.globalPosition).dx;
    _vx = vx < 36 ? -9 : (vx > view.size.width - 36 ? 9 : 0);
    _place();
  }

  /// Picks the gap from the other items' resting positions (not the animated ones), so it never jitters.
  void _place() {
    final d = _drag;
    if (d == null) return;
    _dragX = _finger - _grab;
    final others = widget.items.where((x) => x.id != d.id).toList();
    final (slots, _) = _layout(others);
    final centre = _dragX + (d.isDecor ? _w * .95 : _w) / 2;
    final at = slots.where((s) => s.mid < centre).length;
    if (at != _insertAt) Buzz.tick();
    setState(() => _insertAt = at);
  }

  void _autoScroll(Duration _) {
    if (_drag == null || _vx == 0 || !_sc.hasClients) return;
    final p = _sc.position;
    final next = (p.pixels + _vx).clamp(0.0, p.maxScrollExtent);
    final delta = next - p.pixels;
    if (delta == 0) return;
    _sc.jumpTo(next);
    _finger += delta;
    _place();
  }

  void _dragEnd() {
    if (widget.home) {
      final d = _drag;
      final dy = _dragY;
      final dx = _dragX;
      setState(() {
        _drag = null;
        _insertAt = null;
        _dragY = 0;
      });
      if (d == null) return;
      if (dy < -35) {
        final screenW = MediaQuery.sizeOf(context).width;
        final isSend = dx < (screenW * 0.5);
        Buzz.medium();
        Sfx.play('swoosh');
        openBookShareSheet(context, book: d, initialTab: isSend ? 0 : 1);
      } else {
        Sfx.play('drop');
      }
      return;
    }
    _auto.stop();
    final d = _drag, at = _insertAt;
    Item? anchor;
    var before = true;
    if (d != null && at != null && at != widget.items.indexOf(d)) {
      final others = widget.items.where((x) => x.id != d.id).toList();
      if (at < others.length) {
        anchor = others[at];
      } else if (others.isNotEmpty) {
        anchor = others.last;
        before = false;
      }
    }
    setState(() {
      _drag = null;
      _insertAt = null;
      _vx = 0;
    });
    if (d == null) return;
    Sfx.play('drop');
    Buzz.light();
    if (anchor != null) {
      store.reorder(widget.col, d, anchor, before: before);
      toast(d.isDecor ? 'Decoration moved' : 'Book moved');
    }
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final p = shelfPalettes[widget.palette % shelfPalettes.length];
    final exp = widget.exp;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        key: widget.home ? _boxKey : null,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        child: exp ? _expanded(p) : _row(p),
      ),
      if (!exp)
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _overflow ? _slider() : const SizedBox(width: double.infinity),
        ),
    ]);
  }

  Widget _row(List<Color> p) {
    final (slots, total) = _layout();
    final style = store.settings.shelfStyle;
    final glassH = switch (style) {
      'wood' => 54.0,
      'iron' => 54.0,
      'plastic' => 50.0,
      _ => max(64.0, _h * .45),
    };
    final raised = _drag?.id ?? _pressed;
    final lightsKind = widget.col.lights(sub: widget.sub);
    final stickers = widget.col.stickersFor(sub: widget.sub);

    return LayoutBuilder(builder: (context, cons) {
      final vw = cons.maxWidth;
      final rowH = _h + (lightsKind != null ? 44 : 34);
      final normal = <Widget>[], top = <Widget>[];
      final unraised = <(int, _Slot)>[];
      for (final (i, s) in slots.indexed) {
        if (s.it.id == raised) {
          top.add(_item(s, i, slots));
        } else {
          unraised.add((i, s));
        }
      }
      // Book immediately to the left of CD stays in front (z-index: 2).
      // CD disc leans behind the book (z-index: 1).
      // In Flutter Stack, earlier children are rendered underneath later children.
      unraised.sort((a, b) {
        final (ai, aslot) = a;
        final (bi, bslot) = b;
        final az = (aslot.it.gadget == 'cd' && ai > 0) ? (ai - 1) * 10 - 1 : ai * 10;
        final bz = (bslot.it.gadget == 'cd' && bi > 0) ? (bi - 1) * 10 - 1 : bi * 10;
        return az.compareTo(bz);
      });
      for (final (i, s) in unraised) {
        normal.add(_item(s, i, slots));
      }
      final totalWidth = max(total, vw);
      return Stack(clipBehavior: Clip.none, children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _checkOverflow();
              _reportBounds();
            });
            return false;
          },
          child: SingleChildScrollView(
            key: _viewKey,
            controller: _sc,
            scrollDirection: Axis.horizontal,
            physics: _drag != null ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
            child: SizedBox(
              key: _stackKey,
              width: totalWidth,
              height: rowH,
              child: Stack(clipBehavior: Clip.none, children: [
                if (lightsKind != null)
                  Positioned(
                    left: 0,
                    width: totalWidth,
                    top: 0,
                    height: 38,
                    child: IgnorePointer(child: _HangingLights(kind: lightsKind)),
                  ),
                ...normal,
                // the shelf surface band sits over the books' lower half but stays put while scrolling
                Positioned(
                  left: _sc.hasClients ? _sc.offset : 0,
                  width: vw,
                  bottom: 0,
                  height: glassH,
                  child: IgnorePointer(child: _ShelfBand(p, style: style)),
                ),
                for (final s in stickers)
                  Positioned(
                    left: (s.x / 100 * totalWidth).clamp(10.0, totalWidth - 50.0),
                    bottom: (s.y / 100 * glassH).clamp(4.0, glassH - 24.0),
                    child: _ShelfStickerView(
                      key: ValueKey(s.id),
                      sticker: s,
                      home: widget.home,
                      totalWidth: totalWidth,
                      glassH: glassH,
                      onMoved: (nx, ny) {
                        store.moveSticker(widget.col, s.id, nx, ny);
                      },
                      onRemove: (tear) {
                        store.removeSticker(widget.col, s.id);
                        Sfx.play(tear ? 'tear' : 'pop');
                        toast(tear ? 'Sticker torn off' : 'Sticker removed');
                      },
                    ),
                  ),
                for (final note in widget.col.notesFor(sub: widget.sub))
                  Positioned(
                    left: (note.x / 100 * totalWidth).clamp(10.0, totalWidth - 145.0),
                    bottom: (note.y / 100 * glassH).clamp(2.0, glassH + 20.0),
                    child: StickyNoteWidget(
                      key: ValueKey(note.id),
                      note: note,
                      width: 130,
                      minHeight: 104,
                      canEdit: !widget.home,
                      onMoved: (dx, dy) {
                        final nx = ((note.x / 100 * totalWidth) + dx) / totalWidth * 100;
                        final ny = ((note.y / 100 * glassH) - dy) / glassH * 100;
                        store.moveStickyNote(widget.col, note.id, nx, ny);
                      },
                      onEdited: () => store.changed(),
                      onTear: () {
                        store.removeStickyNote(widget.col, note.id);
                        toast('Note torn off');
                      },
                    ),
                  ),
                if (widget.col.cdFor(sub: widget.sub) != null) ...[
                  Builder(builder: (ctx) {
                    final cd = widget.col.cdFor(sub: widget.sub)!;
                    return Positioned(
                      left: (cd.x / 100 * totalWidth).clamp(8.0, totalWidth - 75.0),
                      bottom: (cd.y / 100 * glassH).clamp(4.0, glassH + 10.0),
                      child: ShelfCdWidget(
                        key: ValueKey(cd.id),
                        cd: cd,
                        home: widget.home,
                        onMoved: (dx, dy) {
                          final nx = ((cd.x / 100 * totalWidth) + dx) / totalWidth * 100;
                          final ny = ((cd.y / 100 * glassH) - dy) / glassH * 100;
                          store.moveCd(widget.col, nx, ny, sub: widget.sub);
                        },
                        onTear: () {
                          store.removeCd(widget.col, sub: widget.sub);
                          toast('CD removed & song deleted');
                        },
                      ),
                    );
                  }),
                ],
                ...top,
              ]),
            ),
          ),
        ),
        if (widget.items.isEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: 18,
            child: IgnorePointer(
              child: Text(
                widget.home ? 'Nothing here yet' : 'Empty shelf · tap ＋ to add a book',
                textAlign: TextAlign.center,
                style: nu(13, FontWeight.w700, C.muted),
              ),
            ),
          ),
        Positioned(left: 12, bottom: 13, right: widget.home ? 12 : 140, child: Align(alignment: Alignment.centerLeft, child: _slab(p))),
        if (!widget.home) Positioned(right: 12, bottom: 10, child: _acts()),
        if (widget.home && _drag != null && _dragY < -25)
          Positioned(
            left: 16,
            right: 16,
            top: -60,
            height: 52,
            child: _DragShareOverlay(
              dragX: _dragX,
              hoverSend: _dragX < (vw * 0.5),
            ),
          ),
      ]);
    });
  }

  Widget _expanded(List<Color> p) {
    final w = _w, h = _h;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 8, 14),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final it in widget.items)
              _tappable(
                it,
                null,
                const [],
                it.isDecor
                    ? (it.gadget == 'cd'
                        ? GadgetView(it.gadget!, w: h * .8, h: h * .8, lit: it.lit)
                        : GadgetView(it.gadget!, w: w * .95, h: h * shelfGadgetFactor(it.gadget!), lit: it.lit))
                    : _Shadowed(child: BookCover(it, w: w, h: h)),
              ),
          ],
        ),
      ),
      Row(children: [
        Flexible(child: Padding(padding: const EdgeInsets.only(left: 8), child: _slab(p))),
        const SizedBox(width: 8),
        if (!widget.home) _acts(),
        const SizedBox(width: 8),
      ]),
    ]);
  }

  Widget _item(_Slot s, int i, List<_Slot> slots) {
    final it = s.it;
    final dragging = _drag?.id == it.id;
    final lifted = _pressed == it.id;
    var dx = 0.0;
    if (_pressed != null && !lifted) {
      if (i > 0 && slots[i - 1].it.id == _pressed) dx = 12;
      if (i < slots.length - 1 && slots[i + 1].it.id == _pressed) dx = -8;
    }
    final Matrix4 m;
    if (dragging) {
      m = Matrix4.identity()
        ..translateByDouble(0, widget.home ? _dragY : -14, 0, 1)
        ..rotateZ(-3 * pi / 180)
        ..scaleByDouble(widget.home ? 1.15 : 1.12, widget.home ? 1.15 : 1.12, 1, 1);
    } else if (lifted) {
      if (it.gadget == 'cd') {
        m = Matrix4.identity()
          ..translateByDouble(0, -8, 0, 1)
          ..rotateZ(3 * pi / 180);
      } else {
        m = Matrix4.identity()
          ..translateByDouble(0, -16, 0, 1)
          ..rotateZ(-4 * pi / 180)
          ..scaleByDouble(1.1, 1.1, 1, 1);
      }
    } else {
      m = Matrix4.identity()..translateByDouble(dx, 0, 0, 1);
    }
    final shadows = <BoxShadow>[
      if (!it.isDecor && dragging) const BoxShadow(color: Color.fromRGBO(0, 0, 0, .4), offset: Offset(0, 16), blurRadius: 26),
      if (!it.isDecor && lifted && !dragging) ...const [
        BoxShadow(color: Color.fromRGBO(40, 20, 5, .45), offset: Offset(0, 18), blurRadius: 22, spreadRadius: -6),
        BoxShadow(color: Color.fromRGBO(0, 0, 0, .2), offset: Offset(0, 4), blurRadius: 8),
      ],
      if (!it.isDecor && !lifted && !dragging) const BoxShadow(color: Color.fromRGBO(0, 0, 0, .28), offset: Offset(0, 2), blurRadius: 6),
    ];
    final dur = dragging ? Duration.zero : const Duration(milliseconds: 380);
    Widget face = it.isDecor
        ? GadgetView(it.gadget!, w: s.w, h: s.h, lit: it.lit)
        : AnimatedBuilder(
            animation: _shine,
            builder: (_, _) => BookCover(it, w: s.w, h: s.h, shine: lifted ? _shine.value : 0),
          );
    if (_fresh.contains(it.id)) {
      face = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 550),
        curve: springCurve,
        onEnd: () => _fresh.remove(it.id),
        builder: (_, t, c) => Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, -16 * (1 - t)),
            child: Transform.scale(scale: .75 + .25 * t, child: c),
          ),
        ),
        child: face,
      );
    }
    return AnimatedPositioned(
      key: ValueKey(it.id),
      duration: dur,
      curve: ease,
      left: dragging ? _dragX : s.x,
      bottom: 14,
      width: s.w,
      height: s.h,
      child: _tappable(
        it,
        s,
        slots,
        AnimatedContainer(
          duration: dur,
          curve: ease,
          transform: m,
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), boxShadow: shadows),
          child: face,
        ),
      ),
    );
  }

  Widget _tappable(Item it, _Slot? s, List<_Slot> slots, Widget child) {
    final label = it.isDecor ? '${gadgetName(it.gadget!)} decoration' : '${it.title} by ${it.author}';
    return Semantics(
      button: true,
      label: label,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (t) => t
              ..onTapDown = ((_) => _tapDown(it))
              ..onTapUp = ((_) => _tapUp(it))
              ..onTapCancel = (() {
                if (_pressed == it.id) setState(() => _pressed = null);
              }),
          ),
          if (_canDrag && s != null)
            LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 320)),
              (l) => l
                ..onLongPressStart = ((d) => _dragStart(it, s, d))
                ..onLongPressMoveUpdate = _dragMove
                ..onLongPressEnd = ((_) => _dragEnd())
                ..onLongPressCancel = (() {
                  if (_drag != null) _dragEnd();
                }),
            ),
        },
        child: child,
      ),
    );
  }

  Widget _slab(List<Color> p) {
    final c = widget.col;
    final n = widget.count;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 248, 236, .85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(184, 105, 42, .25)),
        boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .2), offset: Offset(0, 1), blurRadius: 3)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text('${c.emoji} ${c.name}${widget.sub ? ' · sub shelf' : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(14, FontWeight.w800, lightPal.ink)),
        ),
        const SizedBox(width: 8),
        Container(width: 6, height: 6, decoration: BoxDecoration(color: p[3], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$n${widget.filtered ? '' : '/$shelfMax'} ${n == 1 ? 'book' : 'books'}', style: nu(12, FontWeight.w700, lightPal.muted)),
      ]),
    );
  }

  Widget _acts() {
    Widget b(String t, String label, VoidCallback? f, {double size = 20}) => Semantics(
          button: true,
          label: label,
          child: Pressable(
            onTap: f,
            scale: .88,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(left: 6),
              decoration: const BoxDecoration(color: Color.fromRGBO(255, 255, 255, .8), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(t, style: nu(size, FontWeight.w700, lightPal.ink, 1)),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (!widget.sub && widget.onMore != null) b('⋯', 'Shelf options for ${widget.col.name}', widget.onMore, size: 22),
      b('+', 'Add a book to ${widget.col.name}', widget.onAdd),
      b('🪴', 'Add a decoration', widget.onDecor, size: 17),
    ]);
  }

  Widget _slider() {
    final max = _sc.hasClients ? _sc.position.maxScrollExtent : 1.0;
    final v = _sc.hasClients && max > 0 ? (_sc.offset / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 2, 30, 0),
      child: SizedBox(
        height: 28,
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            activeTrackColor: C.track,
            inactiveTrackColor: C.track,
            thumbShape: const _PillThumb(),
            overlayShape: SliderComponentShape.noOverlay,
            trackShape: const RoundedRectSliderTrackShape(),
            padding: EdgeInsets.zero,
          ),
          child: Slider(
            value: v,
            onChanged: (x) => _sc.jumpTo(x * max),
            semanticFormatterCallback: (_) => 'Slide shelf left and right',
          ),
        ),
      ),
    );
  }
}

class _ShelfBand extends StatelessWidget {
  final List<Color> p;
  final String style;
  const _ShelfBand(this.p, {this.style = 'glass'});

  @override
  Widget build(BuildContext context) {
    return switch (style) {
      'wood' => _buildWood(),
      'iron' => _buildIron(),
      'plastic' => _buildPlastic(),
      _ => _buildGlass(),
    };
  }

  Widget _buildGlass() => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: [p[0], p[1], p[2]], stops: const [0, .55, 1]),
          border: Border.all(color: Colors.white.withValues(alpha: .5), width: 1),
          boxShadow: const [
            BoxShadow(color: Color.fromRGBO(60, 30, 10, .25), offset: Offset(0, 6), blurRadius: 10, spreadRadius: -4),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CustomPaint(painter: _GlassSheenPainter()),
        ),
      );

  Widget _buildWood() => DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(6),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFD49B62), Color(0xFFA8713B), Color(0xFF6E431F)],
          ),
          border: Border(
            top: BorderSide(color: Color(0x99FFE1B4), width: 2),
            bottom: BorderSide(color: Color(0x59321905), width: 3),
          ),
          boxShadow: [
            BoxShadow(color: Color.fromRGBO(40, 20, 5, .45), offset: Offset(0, 8), blurRadius: 12, spreadRadius: -4),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(6),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
          child: CustomPaint(painter: _WoodGrainPainter()),
        ),
      );

  Widget _buildIron() => DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF7E8691), Color(0xFF454B52), Color(0xFF33383E), Color(0xFF22262A)],
            stops: [0, .2, .6, 1],
          ),
          border: Border(
            top: BorderSide(color: Color(0x66FFFFFF), width: 2),
            bottom: BorderSide(color: Color(0x80000000), width: 2),
          ),
          boxShadow: [
            BoxShadow(color: Color.fromRGBO(0, 0, 0, .5), offset: Offset(0, 8), blurRadius: 12, spreadRadius: -4),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
          child: CustomPaint(painter: _IronRivetPainter()),
        ),
      );

  Widget _buildPlastic() => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: p.length > 3 ? p[3] : const Color(0xFFF48AA0),
          border: const Border(
            top: BorderSide(color: Color(0xB3FFFFFF), width: 2),
            bottom: BorderSide(color: Color(0x2E000000), width: 3),
          ),
          boxShadow: const [
            BoxShadow(color: Color.fromRGBO(40, 20, 5, .35), offset: Offset(0, 8), blurRadius: 10, spreadRadius: -4),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99FFFFFF), Color(0x00FFFFFF), Color(0x2E000000)],
                stops: [0, .46, 1],
              ),
            ),
          ),
        ),
      );
}

class _GlassSheenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment(-1, -0.6),
        end: Alignment(1, 0.6),
        colors: [
          Colors.transparent,
          Color(0x44FFFFFF),
          Colors.transparent,
          Colors.transparent,
          Color(0x22FFFFFF),
          Colors.transparent,
        ],
        stops: [0.18, 0.26, 0.34, 0.60, 0.66, 0.72],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WoodGrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grainPaint = Paint()
      ..color = const Color(0x1F46260C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (double x = 24; x < size.width; x += 38) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grainPaint);
    }
    final lightGrain = Paint()
      ..color = const Color(0x12FFEBC8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (double y = 4; y < size.height; y += 8) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), lightGrain);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _IronRivetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rivetOuter = Paint()..color = const Color(0xFF2B2F34);
    final rivetCenter = Paint()..color = const Color(0xFFAAB1BA);
    final cy = size.height * 0.5;
    for (double x = 20; x < size.width; x += 44) {
      canvas.drawCircle(Offset(x, cy), 3.2, rivetOuter);
      canvas.drawCircle(Offset(x, cy), 1.8, rivetCenter);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HangingLights extends StatelessWidget {
  final String kind;
  const _HangingLights({required this.kind});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LightsPainter(kind: kind),
    );
  }
}

class _LightsPainter extends CustomPainter {
  final String kind;
  _LightsPainter({required this.kind});

  @override
  void paint(Canvas canvas, Size size) {
    final wirePaint = Paint()
      ..color = const Color(0xFF4A3A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    final multiColors = const [
      Color(0xFFFF6B6B),
      Color(0xFFFFD98A),
      Color(0xFF6BCF8F),
      Color(0xFF6BB5FF),
      Color(0xFFC58BFF),
    ];

    const swagWidth = 105.0;
    final swags = (size.width / swagWidth).ceil();
    var colorIdx = 0;

    for (int i = 0; i < swags; i++) {
      final x1 = i * swagWidth;
      final x2 = min((i + 1) * swagWidth, size.width);
      final midX = (x1 + x2) / 2;
      const dropY = 16.0;

      final wire = Path()
        ..moveTo(x1, 4)
        ..quadraticBezierTo(midX, dropY + 4, x2, 4);
      canvas.drawPath(wire, wirePaint);

      for (double t = 0.18; t <= 0.82; t += 0.22) {
        final bx = (1 - t) * (1 - t) * x1 + 2 * (1 - t) * t * midX + t * t * x2;
        final by = (1 - t) * (1 - t) * 4 + 2 * (1 - t) * t * (dropY + 4) + t * t * 4;

        final bulbColor = kind == 'multi' ? multiColors[colorIdx % multiColors.length] : const Color(0xFFFFD98A);
        colorIdx++;

        canvas.drawCircle(
          Offset(bx, by + 3),
          6.0,
          Paint()
            ..color = bulbColor.withValues(alpha: .5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(bx, by + 3), width: 5.5, height: 8),
          Paint()..color = bulbColor,
        );
        canvas.drawRect(
          Rect.fromCenter(center: Offset(bx, by - 1), width: 3.5, height: 3),
          Paint()..color = const Color(0xFF4A3A2A),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LightsPainter old) => old.kind != kind;
}

class _ShelfStickerView extends StatefulWidget {
  final ShelfSticker sticker;
  final bool home;
  final double totalWidth;
  final double glassH;
  final void Function(double newX, double newY) onMoved;
  final void Function(bool tear) onRemove;

  const _ShelfStickerView({
    super.key,
    required this.sticker,
    required this.home,
    required this.totalWidth,
    required this.glassH,
    required this.onMoved,
    required this.onRemove,
  });

  @override
  State<_ShelfStickerView> createState() => _ShelfStickerViewState();
}

class _ShelfStickerViewState extends State<_ShelfStickerView> {
  bool _dragging = false;
  double _dragDx = 0;
  double _dragDy = 0;
  bool _didDrag = false;

  @override
  Widget build(BuildContext context) {
    final def = shelfStickers[widget.sticker.kind] ?? shelfStickers['star']!;

    return Transform.translate(
      offset: Offset(_dragDx, _dragDy),
      child: Transform.scale(
        scale: _dragging ? 1.18 : 1.0,
        child: Transform.rotate(
          angle: (widget.sticker.r + (_dragging ? 4.0 : 0.0)) * pi / 180,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              _didDrag = false;
              setState(() {
                _dragging = true;
                _dragDx = 0;
                _dragDy = 0;
              });
              Buzz.tick();
            },
            onPanUpdate: (details) {
              if (details.delta.dx.abs() > 0.4 || details.delta.dy.abs() > 0.4) {
                _didDrag = true;
              }
              setState(() {
                _dragDx += details.delta.dx;
                _dragDy += details.delta.dy;
              });
            },
            onPanEnd: (_) {
              if (_didDrag) {
                // Current pixel coordinates within shelf band
                final curPx = (widget.sticker.x / 100 * widget.totalWidth) + _dragDx;
                // dy is downward, bottom is upward
                final curPy = (widget.sticker.y / 100 * widget.glassH) - _dragDy;
                final newX = (curPx / widget.totalWidth * 100).clamp(2.0, 96.0);
                final newY = (curPy / widget.glassH * 100).clamp(2.0, 90.0);
                widget.onMoved(newX, newY);
                Buzz.tick();
                Sfx.play('tap');
              }
              setState(() {
                _dragging = false;
                _dragDx = 0;
                _dragDy = 0;
              });
            },
            onTap: () {
              if (_didDrag) return;
              Buzz.tick();
              Sfx.play('tap');
              openDialog((ctx) => AppDialog(
                    title: '${def.name} sticker',
                    children: [
                      Center(
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: SvgPicture.string(def.svg),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Drag this sticker to move it anywhere across your shelf. Tap Tear off to tear it away, or Remove to take it off cleanly.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                    actions: [
                      const Btn('Cancel'),
                      Btn('Tear off', kind: Kind.pri, onTap: () {
                        widget.onRemove(true);
                        return true;
                      }),
                      Btn('Remove', kind: Kind.dng, onTap: () {
                        widget.onRemove(false);
                        return true;
                      }),
                    ],
                  ));
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: _dragging
                  ? BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    )
                  : null,
              child: SvgPicture.string(def.svg),
            ),
          ),
        ),
      ),
    );
  }
}


class _Shadowed extends StatelessWidget {
  final Widget child;
  const _Shadowed({required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .28), offset: Offset(0, 2), blurRadius: 6)],
        ),
        child: child,
      );
}

/// The 44x18 brown pill thumb from the mockup's range input.
class _PillThumb extends SliderComponentShape {
  const _PillThumb();
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(44, 18);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: 44, height: 18), const Radius.circular(9));
    final c = context.canvas;
    c.drawRRect(r.shift(const Offset(0, 1)), Paint()..color = const Color.fromRGBO(0, 0, 0, .3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    c.drawRRect(r, Paint()..color = C.brown);
  }
}

class _DragShareOverlay extends StatelessWidget {
  final double dragX;
  final bool hoverSend;

  const _DragShareOverlay({required this.dragX, required this.hoverSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF22B1D10),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color.fromRGBO(0, 0, 0, .35), blurRadius: 14, offset: Offset(0, 4)),
        ],
        border: Border.all(color: const Color(0x33FFE1B4), width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: hoverSend ? C.brown : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('📤', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  Text('Drop to Send', style: nu(13, FontWeight.w800, Colors.white)),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 26, color: const Color(0x33FFFFFF)),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: !hoverSend ? C.brown : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('📥', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  Text('Drop to Receive', style: nu(13, FontWeight.w800, Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
