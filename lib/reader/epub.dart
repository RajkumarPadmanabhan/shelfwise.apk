import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import 'source.dart';

// ---------------------------------------------------------------------------
// Parsing (pure Dart, runs in a background isolate)
// ---------------------------------------------------------------------------

class EpRun {
  final String t;
  final bool b, i;
  const EpRun(this.t, {this.b = false, this.i = false});
}

/// 0 paragraph, 1 heading, 2 image, 3 page break (new chapter)
class EpBlock {
  final int kind;
  final int level;
  final List<EpRun> runs;
  final Uint8List? img;
  final bool center;
  const EpBlock(this.kind, {this.level = 0, this.runs = const [], this.img, this.center = false});
  int get length => runs.fold(0, (a, r) => a + r.t.length);
}

class EpBook {
  final String title, author, desc;
  final Uint8List? cover;
  final List<EpBlock> blocks;
  const EpBook(this.title, this.author, this.desc, this.cover, this.blocks);
}

/// Title, author, description and cover only (fast, for pre-filling the Add Book page).
Future<EpBook> readEpubMeta(String path) => compute(_meta, path);
Future<EpBook> readEpub(String path) => compute(_full, path);

EpBook _meta(String path) => _parse(File(path).readAsBytesSync(), body: false);
EpBook _full(String path) => _parse(File(path).readAsBytesSync(), body: true);

String _norm(String path) {
  final out = <String>[];
  for (final p in Uri.decodeFull(path).split('/')) {
    if (p == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else if (p.isNotEmpty && p != '.') {
      out.add(p);
    }
  }
  return out.join('/');
}

String _dir(String path) => path.contains('/') ? path.substring(0, path.lastIndexOf('/') + 1) : '';

Iterable<XmlElement> _byLocal(XmlNode n, String local) => n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

String _stripTags(String s) => s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

EpBook _parse(Uint8List bytes, {required bool body}) {
  final arc = ZipDecoder().decodeBytes(bytes);
  final names = {for (final f in arc.files) f.name: f};
  ArchiveFile? find(String path) => names[path] ?? names[_norm(path)];
  String? text(String path) {
    final b = find(path)?.readBytes();
    return b == null ? null : utf8.decode(b, allowMalformed: true);
  }

  final container = XmlDocument.parse(text('META-INF/container.xml') ?? '');
  final opfPath = _byLocal(container, 'rootfile').first.getAttribute('full-path')!;
  final opfDir = _dir(opfPath);
  final opf = XmlDocument.parse(text(opfPath) ?? '', entityMapping: const XmlDefaultEntityMapping.html5());

  String meta(String local) => _byLocal(opf, local).map((e) => e.innerText.trim()).firstWhere((t) => t.isNotEmpty, orElse: () => '');
  final title = meta('title');
  final author = meta('creator');
  final desc = _stripTags(meta('description'));

  final manifest = <String, (String, String, String)>{}; // id → href, media-type, properties
  for (final it in _byLocal(opf, 'item')) {
    manifest[it.getAttribute('id') ?? ''] = (it.getAttribute('href') ?? '', it.getAttribute('media-type') ?? '', it.getAttribute('properties') ?? '');
  }
  String? coverId;
  for (final e in manifest.entries) {
    if (e.value.$3.contains('cover-image')) coverId = e.key;
  }
  coverId ??= _byLocal(opf, 'meta').where((m) => m.getAttribute('name') == 'cover').map((m) => m.getAttribute('content')).firstOrNull;
  Uint8List? cover;
  final cv = manifest[coverId];
  if (cv != null && cv.$2.startsWith('image/') && !cv.$2.contains('svg')) cover = find(_norm('$opfDir${cv.$1}'))?.readBytes();

  final blocks = <EpBlock>[];
  if (body) {
    for (final ref in _byLocal(opf, 'itemref')) {
      final m = manifest[ref.getAttribute('idref')];
      if (m == null || !(m.$2.contains('html') || m.$1.endsWith('htm') || m.$1.endsWith('html'))) continue;
      final path = _norm('$opfDir${m.$1}');
      final src = text(path);
      if (src == null) continue;
      if (blocks.isNotEmpty) blocks.add(const EpBlock(3));
      final before = blocks.length;
      try {
        final doc = XmlDocument.parse(src, entityMapping: const XmlDefaultEntityMapping.html5());
        final bodyEl = _byLocal(doc, 'body').firstOrNull ?? doc.rootElement;
        _Walker(blocks, _dir(path), (p) => find(p)?.readBytes()).walk(bodyEl);
      } catch (_) {
        // not well-formed: fall back to plain paragraphs
        for (final p in src.split(RegExp(r'</p>|<br\s*/?>|</h\d>', caseSensitive: false))) {
          final t = _stripTags(p.replaceAll(RegExp(r'<(head|style|script)[\s\S]*?</\1>', caseSensitive: false), ''));
          if (t.isNotEmpty) blocks.add(EpBlock(0, runs: [EpRun(_decodeEntities(t))]));
        }
      }
      if (blocks.length == before && blocks.isNotEmpty && blocks.last.kind == 3) blocks.removeLast();
    }
  }
  return EpBook(title, author, desc, cover, blocks);
}

String _decodeEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&rsquo;', '’')
    .replaceAll('&lsquo;', '‘')
    .replaceAll('&rdquo;', '”')
    .replaceAll('&ldquo;', '“')
    .replaceAll('&mdash;', '—');

const _blockTags = {
  'p', 'div', 'section', 'article', 'main', 'header', 'footer', 'aside', 'nav', 'figure', 'figcaption', 'blockquote',
  'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'table', 'thead', 'tbody', 'tr', 'td', 'th', 'pre', 'center', 'body',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr',
};

/// Collapses HTML whitespace (including source line breaks) to single spaces.
String _ws(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

class _Walker {
  final List<EpBlock> out;
  final String dir;
  final Uint8List? Function(String path) read;
  _Walker(this.out, this.dir, this.read);

  final List<EpRun> _buf = [];
  bool _center = false;

  bool _hasBlockChild(XmlElement e) =>
      e.descendants.whereType<XmlElement>().any((c) => _blockTags.contains(c.name.local.toLowerCase()) || c.name.local == 'img');

  void _flush({int kind = 0, int level = 0}) {
    // tidy whitespace across runs
    final runs = <EpRun>[];
    for (final r in _buf) {
      var t = r.t.replaceAll(RegExp(r'[ \t\r\f\v ]+'), ' ').replaceAll(' \n', '\n').replaceAll('\n ', '\n');
      if (runs.isEmpty) t = t.trimLeft();
      if (t.isEmpty) continue;
      if (runs.isNotEmpty && runs.last.b == r.b && runs.last.i == r.i) {
        final prev = runs.removeLast();
        var joined = prev.t + t;
        joined = joined.replaceAll(RegExp(r' {2,}'), ' ');
        runs.add(EpRun(joined, b: r.b, i: r.i));
      } else {
        if (runs.isNotEmpty && runs.last.t.endsWith(' ') && t.startsWith(' ')) t = t.substring(1);
        runs.add(EpRun(t, b: r.b, i: r.i));
      }
    }
    _buf.clear();
    while (runs.isNotEmpty && runs.last.t.trimRight().isEmpty) {
      runs.removeLast();
    }
    if (runs.isEmpty) return;
    final last = runs.removeLast();
    runs.add(EpRun(last.t.trimRight(), b: last.b, i: last.i));
    out.add(EpBlock(kind, level: level, runs: runs, center: _center || kind == 1));
  }

  void _image(XmlElement e) {
    final src = e.getAttribute('src') ?? e.getAttribute('href') ?? e.getAttribute('xlink:href') ??
        e.attributes.where((a) => a.name.local == 'href').map((a) => a.value).firstOrNull;
    if (src == null || src.toLowerCase().endsWith('.svg')) return;
    final bytes = read(_norm('$dir$src'));
    if (bytes == null || bytes.length > 6 * 1024 * 1024) return;
    _flush();
    out.add(EpBlock(2, img: bytes));
  }

  void walk(XmlElement el) {
    for (final n in el.children) {
      if (n is XmlText || n is XmlCDATA) {
        _buf.add(EpRun(_ws(n.value ?? '')));
        continue;
      }
      if (n is! XmlElement) continue;
      final tag = n.name.local.toLowerCase();
      if (const {'script', 'style', 'head', 'title'}.contains(tag)) continue;
      if (tag == 'img' || tag == 'image') {
        _image(n);
      } else if (tag == 'br') {
        _buf.add(const EpRun('\n'));
      } else if (tag == 'hr') {
        _flush();
      } else if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
        _flush();
        _inline(n, false, false);
        _flush(kind: 1, level: int.parse(tag.substring(1)));
      } else if (tag == 'svg') {
        for (final i in n.descendants.whereType<XmlElement>().where((x) => x.name.local == 'image')) {
          _image(i);
        }
      } else if (_blockTags.contains(tag)) {
        _flush();
        final wasCenter = _center;
        final style = (n.getAttribute('style') ?? '') + (n.getAttribute('class') ?? '');
        if (tag == 'center' || style.contains('center')) _center = true;
        if (_hasBlockChild(n)) {
          walk(n);
        } else {
          if (tag == 'li') _buf.add(const EpRun('•  '));
          _inline(n, false, false);
        }
        _flush();
        _center = wasCenter;
      } else {
        _inline(n, false, false, root: n);
      }
    }
  }

  void _inline(XmlNode n, bool b, bool i, {XmlNode? root}) {
    final kids = root == null ? n.children : [root];
    for (final c in kids) {
      if (c is XmlText || c is XmlCDATA) {
        _buf.add(EpRun(_ws(c.value ?? ''), b: b, i: i));
      } else if (c is XmlElement) {
        final tag = c.name.local.toLowerCase();
        if (const {'script', 'style'}.contains(tag)) continue;
        if (tag == 'br') {
          _buf.add(const EpRun('\n'));
        } else if (tag == 'img' || tag == 'image') {
          _image(c);
        } else {
          final nb = b || tag == 'b' || tag == 'strong' || RegExp(r'^h[1-6]$').hasMatch(tag);
          final ni = i || tag == 'i' || tag == 'em' || tag == 'cite';
          _inline(c, nb, ni);
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Typesetting (UI isolate: TextPainter)
// ---------------------------------------------------------------------------

class _Piece {
  final int block, from, to;
  final double y, h, w;
  const _Piece(this.block, this.from, this.to, this.y, this.h, [this.w = 0]);
  List<num> toJson() => [block, from, to, y, h, w];
  static _Piece fromJson(List l) =>
      _Piece(l[0] as int, l[1] as int, l[2] as int, (l[3] as num).toDouble(), (l[4] as num).toDouble(), (l[5] as num).toDouble());
}

class _Page {
  final List<_Piece> pieces;
  final int offset;
  const _Page(this.pieces, this.offset);
}

const _ink = Color(0xFF1D1A16);
const _paperColor = Color(0xFFFFFDF7);

/// An EPUB laid out into fixed-size pages that render to images.
class EpubSource implements PageSource {
  final String path;
  EpBook? _book;
  List<List<EpRun>> _display = [];
  List<int> _starts = [];
  List<_Page> _pages = [];
  Size _size = Size.zero;
  double _fs = 18;
  final _imgCache = <int, ui.Image>{};

  EpubSource(this.path);

  EpBook? get book => _book;
  double get fontSize => _fs;
  Size get pageSize => _size;

  @override
  int get count => _pages.length;

  @override
  bool get reflows => true;

  @override
  double aspectOf(int i) => _size.isEmpty ? .7 : _size.width / _size.height;

  @override
  Future<void> open() async {
    _book = await readEpub(path);
    final blocks = _book!.blocks;
    // display text: paragraphs that follow another paragraph get a first-line indent
    _display = [
      for (final (i, b) in blocks.indexed)
        if (b.kind == 0 && !b.center && i > 0 && blocks[i - 1].kind == 0) [const EpRun(' '), ...b.runs] else b.runs,
    ];
    // global character offset where each block starts (positions survive re-pagination)
    _starts = [];
    var acc = 0;
    for (final (i, d) in _display.indexed) {
      _starts.add(acc);
      // images count as one character so a picture page and the text after it never share a position
      acc += blocks[i].kind == 2 ? 1 : d.fold<int>(0, (a, r) => a + r.t.length);
    }
  }

  TextStyle _style(EpBlock b, EpRun r) {
    final head = b.kind == 1;
    final scale = !head ? 1.0 : (b.level <= 1 ? 1.55 : b.level == 2 ? 1.35 : 1.18);
    return TextStyle(
      fontFamily: 'Lora',
      fontSize: _fs * scale,
      height: head ? 1.25 : 1.5,
      color: _ink,
      fontWeight: head || r.b ? FontWeight.w700 : FontWeight.w500,
      fontStyle: r.i ? FontStyle.italic : FontStyle.normal,
    );
  }

  TextSpan _span(int bi, int from, int to) {
    final b = _book!.blocks[bi];
    final kids = <TextSpan>[];
    var pos = 0;
    for (final r in _display[bi]) {
      final s = pos, e = pos + r.t.length;
      pos = e;
      if (e <= from || s >= to) continue;
      kids.add(TextSpan(text: r.t.substring(max(0, from - s), min(r.t.length, to - s)), style: _style(b, r)));
    }
    return TextSpan(children: kids, style: TextStyle(fontFamily: 'Lora', fontSize: _fs, color: _ink));
  }

  TextPainter _painter(int bi, int from, int to, double width) {
    final b = _book!.blocks[bi];
    return TextPainter(
      text: _span(bi, from, to),
      textAlign: b.center ? TextAlign.center : TextAlign.justify,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
  }

  double get _mx => max(22, _size.width * .07);
  double get _top => max(26, _size.height * .05);
  double get _bottom => _size.height - max(34, _size.height * .06);

  Future<File> _cacheFile() async {
    final dir = await getTemporaryDirectory();
    final name = path.split('/').last;
    return File('${dir.path}/epub_${name}_${_fs.round()}_${_size.width.round()}x${_size.height.round()}_v4.json');
  }

  /// Splits the book into pages of [size] at [fontSize]. Cached per size on disk.
  Future<void> paginate(Size size, double fontSize, {void Function(double)? onProgress}) async {
    _size = size;
    _fs = fontSize;
    final cf = await _cacheFile();
    if (cf.existsSync()) {
      try {
        final j = jsonDecode(await cf.readAsString()) as List;
        _pages = [for (final p in j) _Page([for (final x in (p as Map)['p'] as List) _Piece.fromJson(x as List)], p['o'] as int)];
        if (_pages.isNotEmpty) return;
      } catch (_) {}
    }
    final blocks = _book!.blocks;
    final cw = size.width - _mx * 2;
    final pages = <_Page>[];
    var cur = <_Piece>[];
    var y = _top;
    var offset = 0;
    void newPage() {
      if (cur.isNotEmpty) pages.add(_Page(cur, offset));
      cur = [];
      y = _top;
    }

    for (var bi = 0; bi < blocks.length; bi++) {
      if (bi % 30 == 0) {
        onProgress?.call(bi / max(1, blocks.length));
        await Future<void>.delayed(Duration.zero);
      }
      final b = blocks[bi];
      if (cur.isEmpty) offset = _starts[bi];
      if (b.kind == 3) {
        newPage();
        continue;
      }
      if (b.kind == 2) {
        Size dim;
        try {
          final codec = await ui.instantiateImageCodec(b.img!);
          final f = await codec.getNextFrame();
          dim = Size(f.image.width.toDouble(), f.image.height.toDouble());
          f.image.dispose();
        } catch (_) {
          continue;
        }
        final s = min(cw / dim.width, (_bottom - _top) * .92 / dim.height);
        final w = dim.width * s, h = dim.height * s;
        if (y + h > _bottom && cur.isNotEmpty) newPage();
        if (cur.isEmpty) offset = _starts[bi];
        cur.add(_Piece(bi, 0, 0, y, h, w));
        y += h + _fs * .8;
        continue;
      }
      final len = _display[bi].fold<int>(0, (a, r) => a + r.t.length);
      var from = 0;
      if (b.kind == 1 && cur.isNotEmpty) y += _fs * 1.1;
      while (from < len) {
        final tp = _painter(bi, from, len, cw);
        final avail = _bottom - y;
        if (tp.height <= avail) {
          cur.add(_Piece(bi, from, len, y, tp.height));
          y += tp.height + (b.kind == 1 ? _fs * .9 : _fs * .45);
          from = len;
        } else {
          // headings never split: move them to the next page
          if (b.kind == 1 && cur.isNotEmpty) {
            newPage();
            offset = _starts[bi] + from;
            continue;
          }
          final lines = tp.computeLineMetrics();
          var k = 0;
          for (final l in lines) {
            if (l.baseline + l.descent > avail) break;
            k++;
          }
          if (k == 0) {
            if (cur.isNotEmpty) {
              newPage();
              offset = _starts[bi] + from;
              continue;
            }
            k = 1; // an empty page always takes at least one line
          }
          if (k >= lines.length) {
            cur.add(_Piece(bi, from, len, y, tp.height));
            y += tp.height;
            from = len;
            continue;
          }
          final next = lines[k];
          final cutY = next.baseline - next.ascent;
          var cut = tp.getPositionForOffset(Offset(1, cutY + 1)).offset;
          if (cut <= 0) cut = 1;
          cur.add(_Piece(bi, from, len, y, cutY));
          from += cut;
          while (from < len && _charAt(bi, from) == ' ') {
            from++;
          }
          newPage();
          offset = _starts[bi] + from;
        }
      }
    }
    newPage();
    _pages = pages;
    onProgress?.call(1);
    try {
      await cf.writeAsString(jsonEncode([
        for (final p in pages) {'o': p.offset, 'p': [for (final x in p.pieces) x.toJson()]},
      ]));
    } catch (_) {}
  }

  String _charAt(int bi, int at) {
    var pos = 0;
    for (final r in _display[bi]) {
      if (at < pos + r.t.length) return r.t[at - pos];
      pos += r.t.length;
    }
    return '';
  }

  int offsetOfPage(int i) => _pages.isEmpty ? 0 : _pages[i.clamp(0, _pages.length - 1)].offset;

  int pageOfOffset(int o) {
    var lo = 0, hi = _pages.length - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (_pages[mid].offset <= o) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    // image-only pages share their offset with the page after; land on the first of them
    while (ans > 0 && _pages[ans - 1].offset == _pages[ans].offset) {
      ans--;
    }
    return ans;
  }

  @override
  Future<ui.Image?> render(int i, double widthPx) async {
    if (i < 0 || i >= _pages.length) return null;
    final k = widthPx / _size.width;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.scale(k);
    c.drawRect(Offset.zero & _size, Paint()..color = _paperColor);
    final cw = _size.width - _mx * 2;
    for (final p in _pages[i].pieces) {
      final b = _book!.blocks[p.block];
      if (b.kind == 2) {
        final img = await _image(p.block);
        if (img == null) continue;
        final dst = Rect.fromLTWH((_size.width - p.w) / 2, p.y, p.w, p.h);
        c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.medium);
        continue;
      }
      // lay out the whole remainder and clip, so line breaks match the pagination exactly
      final tp = _painter(p.block, p.from, p.to, cw);
      c.save();
      c.clipRect(Rect.fromLTWH(0, p.y - 2, _size.width, p.h + 2));
      tp.paint(c, Offset(_mx, p.y));
      c.restore();
    }
    final num = TextPainter(
      text: TextSpan(text: '${i + 1}', style: TextStyle(fontFamily: 'Lora', fontSize: _fs * .7, color: const Color(0xFF8C8273))),
      textDirection: TextDirection.ltr,
    )..layout();
    num.paint(c, Offset((_size.width - num.width) / 2, _size.height - max(22, _size.height * .04) - num.height / 2));
    final pic = rec.endRecording();
    final img = await pic.toImage(widthPx.round(), (_size.height * k).round());
    pic.dispose();
    return img;
  }

  Future<ui.Image?> _image(int bi) async {
    final hit = _imgCache[bi];
    if (hit != null) return hit;
    try {
      final f = await (await ui.instantiateImageCodec(_book!.blocks[bi].img!)).getNextFrame();
      if (_imgCache.length > 6) _imgCache.remove(_imgCache.keys.first)?.dispose();
      return _imgCache[bi] = f.image;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    for (final i in _imgCache.values) {
      i.dispose();
    }
    _imgCache.clear();
  }
}
