import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../services/book_files.dart';
import '../services/lookup.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/common.dart';
import '../widgets/stars.dart';
import 'scan_screen.dart';

Route<void> addBookRoute({Collection? col, bool sub = false}) => PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => AddBookScreen(col: col, sub: sub),
      transitionsBuilder: (_, a, _, child) {
        final t = CurvedAnimation(parent: a, curve: ease, reverseCurve: Curves.easeIn);
        return SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(t),
          child: child,
        );
      },
    );

/// A full page for adding a book, with a live cover preview.
class AddBookScreen extends StatefulWidget {
  final Collection? col;
  final bool sub;
  const AddBookScreen({super.key, this.col, this.sub = false});

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> with SingleTickerProviderStateMixin {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _desc = TextEditingController();
  final _newShelf = TextEditingController();
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  String _status = 'r';
  String? _cover;
  Collection? _col;
  bool _creating = false;
  String _err = '';
  PickedCopy? _copy;
  bool _saved = false;
  int _rating = 0;
  String _isbn = '';
  bool _looking = false;

  @override
  void initState() {
    super.initState();
    _col = widget.col ?? (store.cols.isEmpty ? null : store.cols.firstWhere((c) => store.placeFor(c) != null, orElse: () => store.cols.first));
    _creating = store.cols.isEmpty;
    for (final c in [_title, _author]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    if (!_saved && _copy != null) {
      final f = store.bookFile(_copy!.file);
      if (f.existsSync()) f.deleteSync();
    }
    _shake.dispose();
    for (final c in [_title, _author, _desc, _newShelf]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 700, imageQuality: 85);
    if (x == null) return;
    final name = await store.saveImage(await x.readAsBytes());
    setState(() => _cover = name);
    Sfx.play('pop');
  }

  Future<void> _attach() async {
    final c = await pickBookCopy();
    if (c == null || !mounted) return;
    final old = _copy;
    if (old != null) {
      final f = store.bookFile(old.file);
      if (f.existsSync()) f.deleteSync();
    }
    String? cover;
    if (_cover == null && c.cover != null) cover = await store.saveImage(c.cover!);
    if (!mounted) return;
    setState(() {
      _copy = c;
      if (_title.text.trim().isEmpty) _title.text = c.suggestedTitle;
      if (_author.text.trim().isEmpty && c.author.isNotEmpty) _author.text = c.author;
      if (_desc.text.trim().isEmpty && c.desc.isNotEmpty) _desc.text = c.desc.length > 240 ? '${c.desc.substring(0, 237)}…' : c.desc;
      _cover ??= cover;
    });
    Sfx.play('pop');
    toast(c.isEpub ? 'EPUB attached' : 'PDF attached · ${plural(c.pages, 'page')}');
  }

  Future<void> _scan() async {
    final isbn = await scanIsbn();
    if (isbn == null || !mounted) return;
    setState(() {
      _looking = true;
      _isbn = isbn;
      _err = '';
    });
    final info = await lookupIsbn(isbn);
    if (!mounted) return;
    if (info == null) {
      setState(() => _looking = false);
      Sfx.play('knock');
      toast('Couldn’t find ISBN $isbn. Fill it in by hand.');
      return;
    }
    final cover = info.cover == null ? null : await store.saveImage(info.cover!);
    if (!mounted) return;
    setState(() {
      _looking = false;
      _title.text = info.title;
      if (info.author.isNotEmpty) _author.text = info.author;
      if (info.desc.isNotEmpty) _desc.text = info.desc;
      if (cover != null) _cover = cover;
    });
    Sfx.play('pop');
    Buzz.light();
    toast('Found “${info.title}”');
  }

  void _fail(String m) {
    setState(() => _err = m);
    _shake.forward(from: 0);
    Buzz.medium();
  }

  void _save() {
    final t = _title.text.trim();
    if (t.isEmpty) return _fail('Give the book a title.');
    Collection? c = _col;
    if (_creating) {
      final n = _newShelf.text.trim();
      if (n.isEmpty) return _fail('Name your new shelf.');
      c = store.cols.where((x) => x.name.toLowerCase() == n.toLowerCase()).firstOrNull;
      if (c == null) {
        c = Collection(name: n);
        store.cols.add(c);
      }
    }
    if (c == null) return _fail('Pick a shelf.');
    final a = _author.text.trim().isEmpty ? 'Unknown author' : _author.text.trim();
    if (c.books.any((b) => b.title.toLowerCase() == t.toLowerCase() && b.author.toLowerCase() == a.toLowerCase())) {
      return _fail('That book is already on that shelf.');
    }
    final bool? sub = widget.col == c && widget.sub && store.bookCount(c, true) < shelfMax ? true : store.placeFor(c);
    if (sub == null) return _fail('That collection is full (20 books). Pick another shelf.');
    final gone = store.addBook(
        c,
        Item(
            title: t,
            author: a,
            desc: _desc.text.trim(),
            status: _status,
            cover: _cover,
            file: _copy?.file,
            pages: _copy?.pages ?? 0,
            rating: _rating,
            isbn: _isbn),
        sub: sub);
    _saved = true;
    Sfx.play('drop');
    Buzz.light();
    toast('Added to “${c.name}”${sub ? ' · sub shelf' : ''}${gone > 0 ? ' · a decoration made room' : ''}');
    Navigator.pop(context);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 2),
        child: Text(t, style: nu(13, FontWeight.w800, C.chipText)),
      );

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final title = _title.text.trim();
    final pal = coverFor(title.isEmpty ? 'Untitled' : title);
    final where = _creating ? null : _col;
    final place = where == null ? false : (widget.col == where && widget.sub && store.bookCount(where, true) < shelfMax ? true : store.placeFor(where));
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        Column(children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(22, mq.padding.top + 12, 22, 24),
            children: [
              Row(children: [
                Pressable(
                  onTap: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('‹ Back', style: nu(15, FontWeight.w800, C.brown)),
                  ),
                ),
              ]),
              const H1('Add a book'),
              const SizedBox(height: 2),
              Text('It lands on your shelf the moment you tap Add.', style: nu(14, FontWeight.w600, C.muted)),
              const SizedBox(height: 14),
              Pill(_looking ? 'Looking it up…' : 'Scan the barcode to fill this in',
                  kind: Kind.outline,
                  expand: true,
                  icon: Icon(Icons.qr_code_scanner_rounded, size: 19, color: C.brown),
                  pad: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  onTap: _looking ? null : _scan),
              const SizedBox(height: 18),
              // live preview
              Center(
                child: Semantics(
                  button: true,
                  label: _cover == null ? 'Upload a cover' : 'Change cover',
                  child: Pressable(
                    onTap: _pick,
                    scale: .96,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: springCurve,
                      builder: (_, v, c) => Transform.rotate(angle: (1 - v) * -.25, child: Transform.scale(scale: .6 + .4 * v, child: c)),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [BoxShadow(color: Color.fromRGBO(40, 20, 5, .35), offset: Offset(0, 10), blurRadius: 18)],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _looking
                              ? const _Looking(key: ValueKey('looking'))
                              : KeyedSubtree(
                            key: ValueKey('${pal.hashCode}|$_cover'),
                            child: CoverFace(
                              title: title.isEmpty ? 'Your next favourite' : title,
                              author: _author.text.trim(),
                              image: _cover,
                              w: 124,
                              h: 176,
                              radius: 6,
                              titleSize: 15,
                              authorSize: 11,
                              titleLines: 5,
                              topBorder: 6,
                              spine: 8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Pill(_cover == null ? 'Upload cover' : 'Change cover', kind: Kind.pri, size: 13, onTap: _pick,
                    pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 9)),
                if (_cover != null) ...[
                  const SizedBox(width: 8),
                  Pill('Remove', size: 13, pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), onTap: () => setState(() => _cover = null)),
                ],
              ]),
              const SizedBox(height: 4),
              Text('Optional. Without one, a coloured cover is used.',
                  textAlign: TextAlign.center, style: nu(12, FontWeight.w600, C.muted)),
              AnimatedBuilder(
                animation: _shake,
                builder: (_, c) => Transform.translate(offset: Offset(sin(_shake.value * pi * 6) * 8 * (1 - _shake.value), 0), child: c),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _label('Title'),
                  AppInput(_title, 'e.g. The Hobbit', caps: TextCapitalization.words),
                ]),
              ),
              _label('Author'),
              AppInput(_author, 'e.g. J. R. R. Tolkien', maxLength: 40, caps: TextCapitalization.words),
              _label('What is it about? (optional)'),
              AppInput(_desc, 'A line or two so future-you remembers', maxLength: 240, lines: 3),
              _label('Your copy (optional)'),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SizeTransition(sizeFactor: a, child: c)),
                child: _copy == null
                    ? Pill('Attach a PDF or EPUB from your phone',
                        key: const ValueKey('none'),
                        kind: Kind.outline,
                        expand: true,
                        icon: const Text('📎', style: TextStyle(fontSize: 15)),
                        pad: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                        onTap: _attach)
                    : Container(
                        key: const ValueKey('pdf'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
                        child: Row(children: [
                          Text(_copy!.isEpub ? '📘' : '📄', style: const TextStyle(fontSize: 26)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${_copy!.isEpub ? 'EPUB' : 'PDF'} attached · you can read it in Shelfwise', style: nu(14, FontWeight.w800)),
                              Text(_copy!.isEpub ? fmtSize(_copy!.bytes) : '${plural(_copy!.pages, 'page')} · ${fmtSize(_copy!.bytes)}',
                                  style: nu(12, FontWeight.w600, C.muted)),
                            ]),
                          ),
                          Pressable(
                            onTap: () {
                              final f = store.bookFile(_copy!.file);
                              if (f.existsSync()) f.deleteSync();
                              setState(() => _copy = null);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text('Remove', style: nu(12, FontWeight.w800, C.brown)),
                            ),
                          ),
                        ]),
                      ),
              ),
              _label('Status'),
              const SizedBox(height: 6),
              Row(children: [
                PopChip('📖 Reading', on: _status == 'r', onTap: () => setState(() => _status = 'r')),
                const SizedBox(width: 10),
                PopChip('✅ Finished', on: _status == 'f', onTap: () => setState(() => _status = 'f')),
              ]),
              _label('Your rating (optional)'),
              StarRating(value: _rating, size: 32, onChanged: (v) => setState(() => _rating = v)),
              _label('Shelf'),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in store.cols)
                  PopChip(
                    '${c.emoji} ${c.name} (${c.books.length})${store.placeFor(c) == null ? ' · full' : ''}',
                    on: !_creating && _col == c,
                    fontSize: 14,
                    pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    onTap: () => setState(() {
                      _col = c;
                      _creating = false;
                    }),
                  ),
                PopChip('＋ New shelf', on: _creating, dashed: !_creating, fontSize: 14,
                    pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), onTap: () => setState(() => _creating = true)),
              ]),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: ease,
                child: _creating
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: AppInput(_newShelf, 'New shelf name', maxLength: 28, autofocus: store.cols.isNotEmpty, caps: TextCapitalization.words),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              if (where != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    place == null
                        ? '“${where.name}” is full (20 books).'
                        : place
                            ? 'The main shelf is full, so this goes on the sub shelf.'
                            : 'Goes on “${where.name}”.',
                    style: nu(12, FontWeight.w700, place == null ? C.error : C.muted),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _err.isEmpty
                      ? const SizedBox(height: 18, key: ValueKey(''))
                      : Text(_err, key: ValueKey(_err), style: nu(13, FontWeight.w700, C.error)),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(22, 10, 22, 12 + mq.padding.bottom),
          decoration: BoxDecoration(color: C.bg, border: Border(top: BorderSide(color: Color(0x0D000000)))),
          child: Pressable(
            onTap: _save,
            scale: .98,
            child: Container(
              height: 56,
              decoration: BoxDecoration(color: C.dark ? C.brown : C.black, borderRadius: BorderRadius.circular(6)),
              alignment: Alignment.center,
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Add to my shelf', style: TextStyle(fontFamily: F.hand, fontSize: 25, fontWeight: FontWeight.w500, color: Colors.white)),
                SizedBox(width: 12),
                Text('⟶', style: TextStyle(fontSize: 22, color: C.orange)),
              ]),
            ),
          ),
        ),
        ]),
        Positioned(left: 0, right: 0, top: 0, height: mq.padding.top, child: ColoredBox(color: C.bg.withValues(alpha: .95))),
      ]),
    );
  }
}

/// Shimmering placeholder cover while an ISBN is looked up.
class _Looking extends StatefulWidget {
  const _Looking({super.key});
  @override
  State<_Looking> createState() => _LookingState();
}

class _LookingState extends State<_Looking> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          width: 124,
          height: 176,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment(-1.5 + _c.value * 3, -.3),
              end: Alignment(-.5 + _c.value * 3, .3),
              colors: [C.chip, C.card, C.chip],
            ),
          ),
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.travel_explore_rounded, color: C.brown, size: 30),
            const SizedBox(height: 8),
            Text('Looking up…', style: nu(12, FontWeight.w800, C.chipText)),
          ]),
        ),
      );
}
