import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../reader/epub.dart';
import '../reader/source.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/fx.dart';
import '../widgets/stars.dart';

const _paper = Color(0xFFFFFDF7);
const _wood = Color(0xFF2B1D10);

/// Opens the attached PDF or EPUB of [b] where it was left off.
Future<void> openReader(Item b) async {
  if (!store.copyExists(b)) {
    toast('This book’s file isn’t on this phone. Attach it again.');
    return;
  }
  Sfx.play('page');
  dropFocus();
  await navKey.currentState!.push(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => ReaderScreen(book: b),
    transitionsBuilder: (_, a, _, c) {
      final t = CurvedAnimation(parent: a, curve: ease);
      return FadeTransition(opacity: t, child: ScaleTransition(scale: Tween(begin: .94, end: 1.0).animate(t), child: c));
    },
  ));
}

/// A paper-like reader for PDFs and EPUBs.
///
/// At normal size, drag a corner (or tap the sides) to curl the page over.
/// Pinch or double-tap to zoom in place; while zoomed, one finger pans and
/// swiping past the page edge (or tapping the sides) slides to the next page.
class ReaderScreen extends StatefulWidget {
  final Item book;
  const ReaderScreen({super.key, required this.book});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with TickerProviderStateMixin {
  Item get b => widget.book;
  PageSource? _src;
  bool _ready = false;
  int _count = 0;
  late int _page = b.page;
  double _aspect = 1 / 1.414;
  String? _err;
  double? _typeset; // EPUB pagination progress
  Size _laidFor = Size.zero;

  final _cache = <int, ui.Image>{};
  final _loading = <int>{};
  final _hi = <int, ui.Image>{};
  final _hiLoading = <int>{};
  Future<void> _queue = Future.value();
  double _renderW = 0;
  Rect _rect = Rect.zero;
  Size _view = Size.zero;
  int _gen = 0; // bumps when an EPUB re-flows, so stale renders are dropped

  // curl (normal size)
  Offset? _t;
  bool _forward = true, _top = false;
  Offset _start = Offset.zero;
  late final AnimationController _anim = AnimationController(vsync: this);
  Offset Function(double)? _path;

  // zoom: screen = _zo + _zs * layout
  double _zs = 1;
  Offset _zo = Offset.zero;
  late final AnimationController _zAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  (double, Offset) _za = (1, Offset.zero), _zb = (1, Offset.zero);

  // sliding between pages while zoomed
  late final AnimationController _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
  int _slideDir = 0;
  Offset _nextZo = Offset.zero;

  // gesture bookkeeping
  String _mode = '';
  double _s0 = 1;
  Offset _o0 = Offset.zero, _f0 = Offset.zero;
  double _over = 0;
  Timer? _tapTimer;
  DateTime? _lastTap;
  Offset _lastTapPos = Offset.zero;

  bool _chrome = true, _hint = false;
  double? _slideValue;

  // reading time
  Timer? _clock;
  DateTime _active = DateTime.now();
  bool _foreground = true;
  int _pendingSec = 0;
  late final AppLifecycleListener _life = AppLifecycleListener(
    onResume: () {
      _foreground = true;
      _active = DateTime.now();
    },
    onPause: () {
      _foreground = false;
      _flushTime();
    },
  );

  bool get _zoomed => _zs > 1.01;
  bool get _epub => b.isEpub;
  EpubSource? get _ep => _src is EpubSource ? _src as EpubSource : null;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _anim.addListener(() {
      if (_path != null) setState(() => _t = _path!(_anim.value));
    });
    _zAnim.addListener(() {
      final v = Curves.easeOutCubic.transform(_zAnim.value);
      setState(() {
        _zs = _za.$1 + (_zb.$1 - _za.$1) * v;
        _zo = Offset.lerp(_za.$2, _zb.$2, v)!;
      });
    });
    _slide.addListener(() => setState(() {}));
    _hint = b.readAt == null;
    _life;
    _clock = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_foreground && _ready && DateTime.now().difference(_active) < const Duration(minutes: 3)) _pendingSec += 5;
      if (_pendingSec >= 30) _flushTime();
    });
    _open();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _tapTimer?.cancel();
    _clock?.cancel();
    _flushTime();
    _life.dispose();
    _anim.dispose();
    _zAnim.dispose();
    _slide.dispose();
    for (final i in [..._cache.values, ..._hi.values]) {
      i.dispose();
    }
    final src = _src;
    _queue.whenComplete(() => src?.close());
    _save();
    super.dispose();
  }

  void _flushTime() {
    if (_pendingSec <= 0) return;
    store.addReading(b, _pendingSec);
    _pendingSec = 0;
    store.changed();
  }

  void _touch() => _active = DateTime.now();

  Future<void> _open() async {
    try {
      final path = store.bookFile(b.file!).path;
      if (_epub) {
        final s = EpubSource(path);
        await s.open();
        if (!mounted) return;
        setState(() => _src = s); // pagination starts once the page size is known
      } else {
        final s = PdfSource(path);
        await s.open();
        final a = await s.measure(min(s.count - 1, max(0, b.page)));
        if (!mounted) {
          await s.close();
          return;
        }
        setState(() {
          _src = s;
          _count = s.count;
          _aspect = a.isFinite && a > 0 ? a : _aspect;
          _page = _page.clamp(0, max(0, _count - 1));
          _ready = true;
        });
        if (b.pages != _count) b.pages = _count;
        _save();
      }
      if (_hint) Future.delayed(const Duration(milliseconds: 4500), () => mounted ? setState(() => _hint = false) : null);
    } catch (e) {
      setState(() => _err = 'This book couldn’t be opened.');
    }
  }

  /// Typesets the EPUB for the current page size and text size, keeping the reading position.
  Future<void> _paginate(Size size, {int? keepOffset}) async {
    final ep = _ep;
    if (ep == null || _typeset != null) return;
    _laidFor = size;
    setState(() => _typeset = 0);
    final offset = keepOffset ?? (ep.count > 0 ? ep.offsetOfPage(_page) : b.pos);
    await ep.paginate(size, store.settings.epubSize, onProgress: (p) {
      if (mounted) setState(() => _typeset = p);
    });
    if (!mounted) return;
    _gen++;
    for (final i in [..._cache.values, ..._hi.values]) {
      i.dispose();
    }
    _cache.clear();
    _hi.clear();
    setState(() {
      _typeset = null;
      _count = ep.count;
      _page = keepOffset == null && b.page < _count && ep.offsetOfPage(b.page) == offset
          ? b.page
          : ep.pageOfOffset(offset).clamp(0, max(0, _count - 1));
      _ready = true;
    });
    b.pages = _count;
    _save();
  }

  void _save() {
    b
      ..page = _page
      ..readAt = DateTime.now().millisecondsSinceEpoch;
    final ep = _ep;
    if (ep != null && ep.count > 0) b.pos = ep.offsetOfPage(_page);
    store.changed();
  }

  // ---------------- rendering ----------------

  void _want(int i) {
    final src = _src;
    if (!_ready || src == null || i < 0 || i >= _count || _cache.containsKey(i) || _loading.contains(i) || _renderW <= 0) return;
    _loading.add(i);
    final w = _renderW, gen = _gen;
    _queue = _queue.then((_) async {
      if (!mounted) return;
      try {
        final img = await src.render(i, w);
        if (img == null) return;
        if (!mounted || gen != _gen) return img.dispose();
        setState(() => _cache[i] = img);
        _evict();
      } catch (_) {
      } finally {
        _loading.remove(i);
      }
    });
  }

  /// A sharper copy of a page for reading zoomed in.
  void _wantHi(int i) {
    final src = _src;
    if (!_ready || src == null || i < 0 || i >= _count || _hi.containsKey(i) || _hiLoading.contains(i) || _renderW <= 0) return;
    _hiLoading.add(i);
    final w = min(_renderW * 2.2, 2000.0), gen = _gen;
    _queue = _queue.then((_) async {
      if (!mounted) return;
      try {
        final img = await src.render(i, w);
        if (img == null) return;
        if (!mounted || gen != _gen) return img.dispose();
        setState(() => _hi[i] = img);
        for (final k in _hi.keys.where((k) => (k - _page).abs() > 1).toList()) {
          _hi.remove(k)?.dispose();
        }
      } catch (_) {
      } finally {
        _hiLoading.remove(i);
      }
    });
  }

  void _evict() {
    final keep = {for (var k = _page - 2; k <= _page + 3; k++) k};
    for (final k in _cache.keys.where((k) => !keep.contains(k)).toList()) {
      _cache.remove(k)?.dispose();
    }
  }

  void _prefetch() {
    for (final i in [_page, _page + 1, _page - 1, _page + 2]) {
      _want(i);
    }
    if (_zs > 1.25) {
      _wantHi(_page);
      _wantHi(_page + 1);
    }
  }

  // ---------------- marks ----------------

  /// The page a mark points at: its saved page while the layout still matches, else found by text position.
  int _markPage(Mark m) {
    final ep = _ep;
    if (ep == null || m.pos < 0 || ep.count == 0) return m.page;
    if (m.page < ep.count && ep.offsetOfPage(m.page) == m.pos) return m.page;
    return ep.pageOfOffset(m.pos);
  }

  Mark? get _markHere {
    for (final m in b.marks) {
      if (_markPage(m) == _page) return m;
    }
    return null;
  }

  void _toggleBookmark() {
    _touch();
    final m = _markHere;
    if (m != null && m.note.isEmpty) {
      b.marks.remove(m);
      toast('Bookmark removed');
      Sfx.play('tap');
    } else if (m == null) {
      // Keep strictly one bookmark per book (removing any previous bookmark, keeping notes)
      b.marks.removeWhere((mark) => mark.note.isEmpty);
      b.marks.add(Mark(page: _page, pos: _ep?.offsetOfPage(_page) ?? -1));
      toast('Bookmarked page ${_page + 1}');
      Sfx.play('pop');
      Buzz.light();
    } else {
      toast('This page has a note. Open Notes to remove it.');
      return;
    }
    store.changed();
    setState(() {});
  }

  void _editNote() {
    _touch();
    final m = _markHere;
    final t = TextEditingController(text: m?.note ?? '');
    openDialog((ctx) => AppDialog(title: 'Note on page ${_page + 1}', children: [
          AppInput(t, 'A thought, a quote, a question…', maxLength: 600, lines: 5, autofocus: true),
        ], actions: [
          if (m != null && m.note.isNotEmpty)
            Btn('Delete', kind: Kind.dng, onTap: () {
              b.marks.remove(m);
              store.changed();
              setState(() {});
              toast('Note deleted');
              return true;
            }),
          const Btn('Cancel'),
          Btn('Save', kind: Kind.pri, onTap: () {
            final v = t.text.trim();
            if (v.isEmpty) return false;
            if (m != null) {
              m.note = v;
            } else {
              b.marks.add(Mark(page: _page, pos: _ep?.offsetOfPage(_page) ?? -1, note: v));
            }
            store.changed();
            setState(() {});
            Sfx.play('pop');
            toast('Note saved on page ${_page + 1}');
            return true;
          }),
        ]));
  }

  void _openMarks() {
    _touch();
    openDialog((ctx) => StatefulBuilder(builder: (ctx, set) {
          final marks = [...b.marks]..sort((x, y) => _markPage(x).compareTo(_markPage(y)));
          return AppDialog(title: 'Bookmarks & notes', maxWidth: 380, children: [
            if (marks.isEmpty)
              const Sub('Nothing yet. Tap 🔖 to bookmark a page, or ✎ to write a note on it.')
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .5),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: marks.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: C.line),
                  itemBuilder: (_, i) {
                    final m = marks[i];
                    final pg = _markPage(m);
                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _jump(pg);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m.note.isEmpty ? '🔖' : '📝', style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Page ${pg + 1}', style: nu(14, FontWeight.w800)),
                              if (m.note.isNotEmpty)
                                Text(m.note, maxLines: 3, overflow: TextOverflow.ellipsis, style: nu(13, FontWeight.w600, C.body, 1.35)),
                            ]),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.close_rounded, size: 18, color: C.muted),
                            onPressed: () {
                              b.marks.remove(m);
                              store.changed();
                              set(() {});
                              setState(() {});
                            },
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
          ], actions: const [
            Btn('Close'),
          ]);
        }));
  }

  void _jump(int target) {
    if (target == _page) return;
    Sfx.play('page');
    if (_zoomed) _zo = _topOf(_zs, _zo);
    _turned(target - _page);
  }

  void _textSize() {
    _touch();
    final sizes = [15.0, 16.5, 18.0, 20.0, 22.0, 25.0];
    openDialog((ctx) => StatefulBuilder(builder: (ctx, set) {
          final cur = store.settings.epubSize;
          final i = sizes.indexWhere((s) => (s - cur).abs() < .3).clamp(0, sizes.length - 1);
          void pick(int k) {
            store.settings.epubSize = sizes[k];
            store.changed();
            set(() {});
          }

          return AppDialog(title: 'Text size', children: [
            Row(children: [
              Pill('A−', size: 16, onTap: i > 0 ? () => pick(i - 1) : null),
              Expanded(
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(fontFamily: 'Lora', fontSize: sizes[i] * 1.1, fontWeight: FontWeight.w600, color: C.ink),
                    child: const Text('Aa'),
                  ),
                ),
              ),
              Pill('A+', size: 16, onTap: i < sizes.length - 1 ? () => pick(i + 1) : null),
            ]),
          ], actions: [
            Btn('Done', kind: Kind.pri, onTap: () {
              final ep = _ep;
              if (ep != null && (ep.fontSize - store.settings.epubSize).abs() > .1) {
                _paginate(_laidFor, keepOffset: ep.offsetOfPage(_page));
              }
              return true;
            }),
          ]);
        }));
  }

  // ---------------- zoom ----------------

  /// Keeps the zoomed page covering the screen (or centred when it's smaller).
  Offset _clampZo(double s, Offset o, {double slack = 0}) {
    double axis(double v, double lo, double size, double view, double centre) {
      final len = size * s;
      if (len <= view) return centre * (1 - s);
      final minV = view - s * (lo + size);
      final maxV = -s * lo;
      return v.clamp(minV - slack, maxV + slack);
    }

    return Offset(
      axis(o.dx, _rect.left, _rect.width, _view.width, _rect.center.dx),
      axis(o.dy, _rect.top, _rect.height, _view.height, _rect.center.dy),
    );
  }

  void _zoomTo(double s, Offset o, {int ms = 280}) {
    _za = (_zs, _zo);
    _zb = (s, s <= 1.01 ? Offset.zero : _clampZo(s, o));
    _zAnim
      ..duration = Duration(milliseconds: ms)
      ..forward(from: 0);
    if (s > 1.25) _wantHi(_page);
  }

  void _toggleZoom(Offset focal) {
    Buzz.tick();
    _touch();
    if (_zoomed) {
      _zoomTo(1, Offset.zero);
    } else {
      const s = 2.2;
      final p = (focal - _zo) / _zs;
      setState(() => _chrome = false);
      _zoomTo(s, focal - p * s);
    }
  }

  /// Where the zoomed view should sit on a freshly turned page: same zoom and column, top of the page.
  Offset _topOf(double s, Offset o) => _clampZo(s, Offset(o.dx, -s * _rect.top));

  // ---------------- turning ----------------

  Offset get _corner => Offset(_rect.right, _top ? _rect.top : _rect.bottom);
  Offset get _flat => Offset(_rect.left - _rect.width, _corner.dy);

  Offset _constrain(Offset t) {
    final s = Offset(_rect.left, _corner.dy);
    var v = t - s;
    if (v.distance > _rect.width) v = v / v.distance * _rect.width;
    t = s + v;
    final s2 = Offset(_rect.left, _top ? _rect.bottom : _rect.top);
    final diag = sqrt(_rect.width * _rect.width + _rect.height * _rect.height);
    var v2 = t - s2;
    if (v2.distance > diag) v2 = v2 / v2.distance * diag;
    t = s2 + v2;
    return Offset(min(t.dx, _corner.dx - .5), t.dy);
  }

  bool get _busy => _anim.isAnimating || _slide.isAnimating || _typeset != null;

  void _run(Offset Function(double) path, int ms, Curve curve, VoidCallback done) {
    _path = (v) => path(curve.transform(v));
    _anim
      ..duration = Duration(milliseconds: ms)
      ..forward(from: 0).whenComplete(() {
        _path = null;
        if (mounted) done();
      });
  }

  void _turned(int delta) {
    _touch();
    setState(() {
      _page = (_page + delta).clamp(0, max(0, _count - 1));
      _t = null;
    });
    _evict();
    _prefetch();
    _save();
  }

  bool _canGo(int dir) {
    if (dir > 0 && _page >= _count - 1) {
      _end();
      return false;
    }
    if (dir < 0 && _page <= 0) {
      toast('This is the first page');
      return false;
    }
    return true;
  }

  void _go(int dir) {
    if (_busy || !_ready || !_canGo(dir)) return;
    if (_zoomed) return _slideTo(dir);
    _want(_page + dir);
    _forward = dir > 0;
    _top = false;
    Sfx.play('page');
    Buzz.tick();
    final c = _corner, f = _flat, h = _rect.height;
    if (dir > 0) {
      _run((p) => Offset(c.dx + (f.dx - c.dx) * p, c.dy - sin(p * pi) * h * .12), 560, Curves.easeInOut, () => _turned(1));
    } else {
      _run((p) => Offset(f.dx + (c.dx - f.dx) * p, c.dy - sin(p * pi) * h * .12), 560, Curves.easeInOut, () => _turned(-1));
    }
  }

  /// Zoomed in: slide the next page across, keeping the zoom.
  void _slideTo(int dir) {
    _want(_page + dir);
    _wantHi(_page + dir);
    _nextZo = _topOf(_zs, _zo);
    _slideDir = dir;
    Sfx.play('page');
    Buzz.tick();
    _slide.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      _zo = _nextZo;
      _slideDir = 0;
      _slide.value = 0;
      _turned(dir);
    });
  }

  void _end() {
    if (b.finished) {
      toast('That’s the last page');
      return;
    }
    var rating = b.rating;
    openDialog((ctx) => StatefulBuilder(
          builder: (ctx, set) => AppDialog(title: 'You reached the end 🎉', children: [
            Sub('That’s the last page of ${b.title}. How was it?'),
            Center(child: StarRating(value: rating, size: 36, onChanged: (v) => set(() => rating = v))),
            const SizedBox(height: 4),
          ], actions: [
            const Btn('Not yet'),
            Btn('Mark as finished', kind: Kind.pri, onTap: () {
              b.rating = rating;
              store.setStatus(b, 'f');
              Sfx.play('trophy');
              final s = MediaQuery.sizeOf(ctx);
              confetti(Offset(s.width / 2, s.height * .4));
              toast('Marked as Finished');
              return true;
            }),
          ]),
        ));
  }

  // ---------------- gestures ----------------

  void _onTapUp(Offset p) {
    _touch();
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < const Duration(milliseconds: 280) && (p - _lastTapPos).distance < 60) {
      _tapTimer?.cancel();
      _lastTap = null;
      _toggleZoom(p);
      return;
    }
    _lastTap = now;
    _lastTapPos = p;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final w = _view.width;
      if (p.dx > w * .66) {
        _go(1);
      } else if (p.dx < w * .3) {
        _go(-1);
      } else {
        setState(() => _chrome = !_chrome);
      }
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _touch();
    if (!_ready || _busy) {
      _mode = '';
      return;
    }
    _zAnim.stop();
    _s0 = _zs;
    _o0 = _zo;
    _f0 = d.localFocalPoint;
    _over = 0;
    if (d.pointerCount >= 2) {
      _mode = 'pinch';
    } else if (_zoomed) {
      _mode = 'pan';
    } else {
      _mode = 'curl';
      _curlStart(d.localFocalPoint);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2 && _mode != 'pinch') {
      if (_mode == 'curl') setState(() => _t = null);
      if (_chrome) setState(() => _chrome = false);
      _mode = 'pinch';
      _s0 = _zs;
      _o0 = _zo;
      _f0 = d.localFocalPoint;
      return;
    }
    switch (_mode) {
      case 'pinch':
        final s = (_s0 * d.scale).clamp(1.0, 5.0);
        final p = (_f0 - _o0) / _s0;
        setState(() {
          _zs = s;
          _zo = s <= 1.01 ? Offset.zero : _clampZo(s, d.localFocalPoint - p * s);
        });
      case 'pan':
        final raw = _o0 + (d.localFocalPoint - _f0);
        final cl = _clampZo(_zs, raw);
        _over = raw.dx - cl.dx;
        setState(() => _zo = Offset(cl.dx + _over * .35, cl.dy));
      case 'curl':
        _curlMove(d.localFocalPoint);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final vx = d.velocity.pixelsPerSecond.dx;
    switch (_mode) {
      case 'pinch':
        if (_zs < 1.08) {
          _zoomTo(1, Offset.zero, ms: 200);
        } else {
          _wantHi(_page);
        }
      case 'pan':
        final cl = _clampZo(_zs, _zo);
        final minX = _clampZo(_zs, Offset(-1e9, cl.dy)).dx, maxX = _clampZo(_zs, Offset(1e9, cl.dy)).dx;
        final atRight = (cl.dx - minX).abs() < 1, atLeft = (cl.dx - maxX).abs() < 1;
        if (_over < -70 || (atRight && vx < -900)) {
          _zo = cl;
          if (_canGo(1)) _slideTo(1);
        } else if (_over > 70 || (atLeft && vx > 900)) {
          _zo = cl;
          if (_canGo(-1)) _slideTo(-1);
        } else if (_over.abs() > .5) {
          _zoomTo(_zs, cl, ms: 220);
        }
      case 'curl':
        _curlEnd(vx);
    }
    _mode = '';
  }

  void _curlStart(Offset p) {
    _forward = p.dx >= _rect.center.dx;
    if (_forward && _page >= _count - 1) return;
    if (!_forward && _page <= 0) return;
    _top = p.dy < _rect.center.dy - _rect.height * .15;
    _start = p;
    _want(_page + (_forward ? 1 : -1));
    _t = null;
  }

  void _curlMove(Offset p) {
    final d = p - _start;
    if (_t == null) {
      if (d.distance < 8) return;
      if (_forward ? _page >= _count - 1 : _page <= 0) return;
      Buzz.tick();
    }
    if (_forward) {
      setState(() => _t = _constrain(_corner + Offset(d.dx * 1.5, d.dy * 1.2)));
    } else {
      final prog = (d.dx / max(1, _rect.right - _start.dx)).clamp(0.0, 1.0);
      final x = _flat.dx + (_corner.dx - _flat.dx) * prog;
      setState(() => _t = _constrain(Offset(x, _corner.dy + d.dy * 1.2)));
    }
  }

  void _curlEnd(double vx) {
    final t = _t;
    if (t == null) return;
    final c = _corner, f = _flat;
    final prog = ((c.dx - t.dx) / (c.dx - f.dx)).clamp(0.0, 1.0);
    if (_forward) {
      if (vx < -350 || (vx < 350 && prog > .4)) {
        Sfx.play('page');
        _run((p) => Offset.lerp(t, f, p)!, (380 * (1 - prog) + 120).round(), Curves.easeOut, () => _turned(1));
      } else {
        _run((p) => Offset.lerp(t, c - const Offset(.6, 0), p)!, (300 * prog + 120).round(), Curves.easeOut, () => setState(() => _t = null));
      }
    } else {
      if (vx > 350 || (vx > -350 && prog < .6)) {
        Sfx.play('page');
        _run((p) => Offset.lerp(t, c - const Offset(.6, 0), p)!, (380 * prog + 120).round(), Curves.easeOut, () => _turned(-1));
      } else {
        _run((p) => Offset.lerp(t, f, p)!, (300 * (1 - prog) + 120).round(), Curves.easeOut, () => setState(() => _t = null));
      }
    }
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return PopScope(
      canPop: !_zoomed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _zoomed) _zoomTo(1, Offset.zero);
      },
      child: Scaffold(
        backgroundColor: _wood,
        resizeToAvoidBottomInset: false, // the keyboard (for notes) must not re-flow the book
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A2816), _wood, Color(0xFF1E140A)]),
          ),
          child: LayoutBuilder(builder: (context, cons) {
            _view = cons.biggest;
            final pad = EdgeInsets.fromLTRB(14, mq.padding.top + 58, 14, mq.padding.bottom + 150);
            final availW = cons.maxWidth - pad.horizontal, availH = cons.maxHeight - pad.vertical;
            final src = _src;
            if (src is EpubSource) {
              final want = Size(availW, availH);
              if (_typeset == null && ((_laidFor.width - want.width).abs() > 2 || (_laidFor.height - want.height).abs() > 2)) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _paginate(want));
              }
              _aspect = availW / availH;
            } else {
              final cur = _cache[_page];
              if (cur != null && _t == null && _slideDir == 0) _aspect = cur.width / cur.height;
            }
            var w = availW, h = w / _aspect;
            if (h > availH) {
              h = availH;
              w = h * _aspect;
            }
            _rect = Rect.fromLTWH(pad.left + (availW - w) / 2, pad.top + (availH - h) / 2, w, h);
            final rw = min(availW * mq.devicePixelRatio, 1500.0);
            if (_ready && (rw - _renderW).abs() > 40) {
              _renderW = rw;
              for (final i in _cache.values) {
                i.dispose();
              }
              _cache.clear();
            }
            if (_ready) WidgetsBinding.instance.addPostFrameCallback((_) => _prefetch());
            final next = _slideDir == 0 ? null : _page + _slideDir;
            return Stack(children: [
              if (_err != null)
                Center(child: Text(_err!, style: nu(16, FontWeight.w700, const Color(0xFFF3EEE6))))
              else if (!_ready || _typeset != null)
                Center(child: _Typesetting(progress: _typeset, epub: _epub))
              else
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onTapUp(d.localPosition),
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    child: CustomPaint(
                      painter: _PagePainter(
                        rect: _rect,
                        front: _zoomed ? (_hi[_page] ?? _cache[_page]) : _cache[_forward || _t == null ? _page : _page - 1],
                        under: _t == null ? null : _cache[_forward ? _page + 1 : _page],
                        t: _zoomed ? null : _t,
                        corner: _t == null ? null : _corner,
                        zs: _zs,
                        zo: _zo,
                        slide: _slide.value,
                        slideDir: _slideDir,
                        next: next == null ? null : (_hi[next] ?? _cache[next]),
                        nextZo: _nextZo,
                        view: _view,
                        marked: _t == null && _slideDir == 0 && _markHere != null,
                      ),
                    ),
                  ),
                ),
              _topBar(mq),
              _bottomBar(mq),
              if (_hint && _ready && _typeset == null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: _rect.center.dy - 30,
                  child: IgnorePointer(
                    child: Center(
                      child: FadeIn(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(color: const Color(0xE62B1D10), borderRadius: BorderRadius.circular(18)),
                          child: Text('Drag a corner or tap the edges to turn\nPinch or double-tap to zoom · tap the middle for controls',
                              textAlign: TextAlign.center, style: nu(13, FontWeight.w700, Colors.white, 1.4)),
                        ),
                      ),
                    ),
                  ),
                ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _circle(Widget child, VoidCallback onTap, String label) => Semantics(
        button: true,
        label: label,
        child: Pressable(
          onTap: onTap,
          scale: .88,
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: Color.fromRGBO(255, 255, 255, .14), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      );

  Widget _topBar(MediaQueryData mq) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        ignoring: !_chrome,
        child: AnimatedOpacity(
          opacity: _chrome ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: AnimatedSlide(
            offset: _chrome ? Offset.zero : const Offset(0, -.4),
            duration: const Duration(milliseconds: 260),
            curve: ease,
            child: Container(
              padding: EdgeInsets.fromLTRB(12, mq.padding.top + 8, 12, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xE61E140A), Color(0x002B1D10)]),
              ),
              child: Row(children: [
                _circle(const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20), () => Navigator.of(context).pop(), 'Close reader'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(16, FontWeight.w800, const Color(0xFFF3EEE6))),
                    Text(
                      b.fromUser != null && b.fromUser!.isNotEmpty
                          ? '${b.author} · 🤝 Book from ${b.fromUser}'
                          : b.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: nu(12, FontWeight.w700, const Color(0xFFCDBFAE)),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                _circle(
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(_zoomed ? Icons.zoom_out_map_rounded : Icons.zoom_in_rounded, key: ValueKey(_zoomed), color: Colors.white, size: 22),
                  ),
                  () => _toggleZoom(_view.center(Offset.zero)),
                  _zoomed ? 'Fit page' : 'Zoom in',
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap, {bool on = false}) => Expanded(
        child: Semantics(
          button: true,
          label: label,
          child: Pressable(
            onTap: onTap,
            scale: .9,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 40,
                height: 34,
                decoration: BoxDecoration(color: on ? const Color(0x33F2B84B) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: on ? const Color(0xFFF2B84B) : const Color(0xFFF3EEE6)),
              ),
              Text(label, style: nu(10.5, FontWeight.w700, const Color(0xFFCDBFAE))),
            ]),
          ),
        ),
      );

  Widget _bottomBar(MediaQueryData mq) {
    final show = _chrome && _count > 0 && _typeset == null;
    final shown = (_slideValue ?? _page.toDouble()).round();
    final pct = _count <= 1 ? 100 : (shown / (_count - 1) * 100).round();
    final here = _markHere;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: AnimatedSlide(
            offset: show ? Offset.zero : const Offset(0, .4),
            duration: const Duration(milliseconds: 260),
            curve: ease,
            child: Container(
              padding: EdgeInsets.fromLTRB(18, 14, 18, mq.padding.bottom + 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x002B1D10), Color(0xE61E140A)]),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Text('Page ${shown + 1} of $_count', style: nu(13, FontWeight.w800, const Color(0xFFF3EEE6))),
                  if (_zoomed) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(10)),
                      child: Text('${_zs.toStringAsFixed(1)}×', style: nu(11, FontWeight.w800, const Color(0xFFF3EEE6))),
                    ),
                  ],
                  const Spacer(),
                  Text('$pct%', style: nu(13, FontWeight.w800, const Color(0xFFF2B84B))),
                ]),
                SliderTheme(
                  data: const SliderThemeData(
                    trackHeight: 4,
                    activeTrackColor: Color(0xFFF2B84B),
                    inactiveTrackColor: Color.fromRGBO(255, 255, 255, .2),
                    thumbColor: Color(0xFFF2B84B),
                    overlayColor: Color(0x33F2B84B),
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                  ),
                  child: Slider(
                    value: (_slideValue ?? _page.toDouble()).clamp(0, max(0, _count - 1).toDouble()),
                    min: 0,
                    max: max(1, _count - 1).toDouble(),
                    onChanged: (v) => setState(() => _slideValue = v),
                    onChangeEnd: (v) {
                      final target = v.round();
                      setState(() => _slideValue = null);
                      _jump(target);
                    },
                  ),
                ),
                Row(children: [
                  _tool(here != null ? Icons.bookmark_rounded : Icons.bookmark_add_outlined, 'Bookmark', _toggleBookmark, on: here != null),
                  _tool(Icons.edit_note_rounded, 'Note', _editNote, on: here != null && here.note.isNotEmpty),
                  _tool(Icons.collections_bookmark_outlined, 'Notes (${b.marks.length})', _openMarks),
                  if (_epub) _tool(Icons.format_size_rounded, 'Text size', _textSize),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Setting the type…" while an EPUB is being laid out into pages.
class _Typesetting extends StatelessWidget {
  final double? progress;
  final bool epub;
  const _Typesetting({required this.progress, required this.epub});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 54,
        height: 54,
        child: CircularProgressIndicator(value: progress, strokeWidth: 4, color: const Color(0xFFF2B84B), backgroundColor: const Color(0x22FFFFFF)),
      ),
      const SizedBox(height: 16),
      Text(epub ? (progress == null ? 'Opening the book…' : 'Setting the type… ${((progress ?? 0) * 100).round()}%') : 'Opening…',
          style: nu(14, FontWeight.w700, const Color(0xFFF3EEE6))),
    ]);
  }
}


/// Draws the page: zoomed and sliding, or flat and curling over like paper.
class _PagePainter extends CustomPainter {
  final Rect rect;
  final ui.Image? front, under, next;
  final Offset? t, corner;
  final double zs, slide;
  final Offset zo, nextZo;
  final int slideDir;
  final Size view;
  final bool marked;
  _PagePainter({
    required this.rect,
    this.front,
    this.under,
    this.t,
    this.corner,
    required this.zs,
    required this.zo,
    required this.slide,
    required this.slideDir,
    this.next,
    required this.nextZo,
    required this.view,
    this.marked = false,
  });

  void _page(Canvas c, ui.Image? img) {
    c.drawRect(rect, Paint()..color = _paper);
    if (img == null) {
      final p = Paint()..color = const Color(0xFFEDE6DA);
      for (var i = 0; i < 14; i++) {
        final y = rect.top + rect.height * (.1 + i * .058);
        c.drawRRect(RRect.fromLTRBR(rect.left + rect.width * .1, y, rect.right - rect.width * (i % 4 == 3 ? .35 : .1), y + 6, const Radius.circular(3)), p);
      }
      return;
    }
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final fit = applyBoxFit(BoxFit.contain, src.size, rect.size);
    final dst = Alignment.center.inscribe(fit.destination, rect);
    c.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.medium);
  }

  void _spine(Canvas c) {
    c.drawRect(
      Rect.fromLTWH(rect.left, rect.top, 22, rect.height),
      Paint()..shader = ui.Gradient.linear(rect.topLeft, rect.topLeft + const Offset(22, 0), [const Color(0x24000000), const Color(0x00000000)]),
    );
  }

  void _ribbon(Canvas c) {
    if (!marked) return;
    final w = max(14.0, rect.width * .045), h = w * 2.4, x = rect.right - w * 2.2;
    final path = Path()
      ..moveTo(x, rect.top - 2)
      ..lineTo(x + w, rect.top - 2)
      ..lineTo(x + w, rect.top + h)
      ..lineTo(x + w / 2, rect.top + h * .78)
      ..lineTo(x, rect.top + h)
      ..close();
    c.drawShadow(path, Colors.black, 3, false);
    c.drawPath(path, Paint()..color = const Color(0xFFF26A21));
  }

  void _shadow(Canvas c) => c.drawRRect(
        RRect.fromRectAndRadius(rect.shift(const Offset(0, 6)), const Radius.circular(4)),
        Paint()
          ..color = const Color(0x8C000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );

  static List<Offset> _clip(List<Offset> poly, double Function(Offset) f) {
    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final fa = f(a), fb = f(b);
      if (fa >= 0) out.add(a);
      if ((fa >= 0) != (fb >= 0)) out.add(a + (b - a) * (fa / (fa - fb)));
    }
    return out;
  }

  void _zoomedPage(Canvas c, ui.Image? img, Offset o, double dx) {
    c.save();
    c.translate(dx, 0);
    c.translate(o.dx, o.dy);
    c.scale(zs);
    _shadow(c);
    _page(c, img);
    if (img == front) _ribbon(c);
    c.restore();
  }

  @override
  void paint(Canvas c, Size size) {
    if (zs > 1.01 || slideDir != 0) {
      final w = view.width;
      final e = Curves.easeInOutCubic.transform(slide);
      _zoomedPage(c, front, zo, -slideDir * w * e);
      if (slideDir != 0) _zoomedPage(c, next, nextZo, slideDir * w * (1 - e));
      return;
    }
    _shadow(c);
    c.save();
    c.clipRect(rect);
    final tt = t, cc = corner;
    if (tt == null || cc == null || (cc - tt).distance < .5) {
      _page(c, front);
      _spine(c);
      c.restore();
      _ribbon(c);
      return;
    }
    final d = cc - tt;
    final n = d / d.distance;
    final m = (cc + tt) / 2;
    double side(Offset p) => (p - m).dx * n.dx + (p - m).dy * n.dy;
    Offset reflect(Offset p) => p - n * (2 * side(p));
    final quad = [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];
    final kept = _clip(quad, (p) => -side(p));
    final removed = _clip(quad, side);
    final keptPath = Path()..addPolygon(kept, true);
    final removedPath = Path()..addPolygon(removed, true);
    final flap = removed.map(reflect).toList();
    final flapPath = Path()..addPolygon(flap, true);
    final depth = min(70.0, d.distance / 2 + 8);

    // 1. the page underneath, darkened next to the fold
    _page(c, under);
    _spine(c);
    c.save();
    c.clipPath(removedPath);
    c.drawRect(rect, Paint()..shader = ui.Gradient.linear(m, m + n * depth, [const Color(0x59000000), const Color(0x00000000)]));
    c.restore();

    // 2. what's left of the current page, with the flap's soft shadow on it
    c.save();
    c.clipPath(keptPath);
    _page(c, front);
    _spine(c);
    c.drawPath(
      flapPath.shift(-n * 4),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    c.restore();

    // 3. the curled-over flap: the back of the paper, ink faintly showing through
    if (flap.length >= 3) {
      c.save();
      c.clipPath(flapPath);
      final a = 1 - 2 * n.dx * n.dx, bb = -2 * n.dx * n.dy, dd = 1 - 2 * n.dy * n.dy;
      final k = 2 * (m.dx * n.dx + m.dy * n.dy);
      c.save();
      c.transform(Float64List.fromList([a, bb, 0, 0, bb, dd, 0, 0, 0, 0, 1, 0, k * n.dx, k * n.dy, 0, 1]));
      _page(c, front);
      c.drawRect(rect, Paint()..color = const Color(0xDBFBF7EE));
      c.restore();
      c.drawRect(
        Rect.largest,
        Paint()..shader = ui.Gradient.linear(m, m - n * depth * 1.6, [const Color(0x2E000000), const Color(0x00FFFFFF), const Color(0x14000000)], [0, .55, 1]),
      );
      c.restore();
      c.drawPath(flapPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = const Color(0x22000000));
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_PagePainter o) => true;
}
