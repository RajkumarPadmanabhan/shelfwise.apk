import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import '../art.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../icons.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/book_share_sheet.dart';
import '../widgets/common.dart';
import '../widgets/copy_panel.dart';
import '../widgets/dialogs.dart';
import '../widgets/fx.dart';
import '../widgets/shelf.dart';
import '../widgets/sticky_note.dart';
import '../widgets/stars.dart';
import '../widgets/update_card.dart';
import 'add_book_screen.dart';
import 'bell.dart';
import 'full_shelf.dart';
import 'reader_screen.dart';

/// Filter state survives tab switches, like the mockup's module variables.
class LibUi {
  static String f = 'all';
  static String q = '';
  static bool exp = false;
}

class LibraryScreen extends StatefulWidget {
  final bool home;
  final VoidCallback onProfile;
  final VoidCallback onTodo;
  final VoidCallback onStats;
  const LibraryScreen({super.key, required this.home, required this.onProfile, required this.onTodo, required this.onStats});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _chips = ScrollController();
  final _q = TextEditingController(text: LibUi.q);
  final _chipKeys = <String, GlobalKey>{};

  bool get home => widget.home;

  static final Set<String> _alertedTodoIds = {};

  @override
  void initState() {
    super.initState();
    if (!home) {
      Future.delayed(const Duration(milliseconds: 650), _nudge);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpcomingTodoAlert());
    }
  }

  void _checkUpcomingTodoAlert() {
    if (!mounted || !home) return;
    final now = DateTime.now();
    final todayEnd = AppStore.endOfToday();
    final todayStart = DateTime(now.year, now.month, now.day);

    final candidates = store.todos.where((t) {
      if (t.done || _alertedTodoIds.contains(t.id)) return false;
      if (t.due != null) {
        final d = t.dueAt!;
        return d.isAfter(todayStart) && d.isBefore(todayEnd.add(const Duration(hours: 1)));
      } else {
        final created = DateTime.fromMillisecondsSinceEpoch(t.createdAt);
        return created.isAfter(todayStart);
      }
    }).toList();

    if (candidates.isEmpty) return;
    final target = candidates.first;
    _alertedTodoIds.add(target.id);

    openDialog((ctx) => AppDialog(
          title: '⏰ To-do Reminder',
          children: [
            Text(
              '${target.text} starts in 1 hr',
              style: nu(16, FontWeight.w800, C.ink, 1.3),
            ),
            if (target.book.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('📖 ${target.book}', style: nu(13, FontWeight.w600, C.muted)),
              ),
            const SizedBox(height: 6),
            Text(
              target.due != null ? 'Scheduled for today (${fmtDue(target.dueAt!)})' : 'Active reading task for today',
              style: nu(12, FontWeight.w600, C.muted),
            ),
          ],
          actions: [
            Btn('Skip', kind: Kind.normal, onTap: () => true),
            Btn('OK', kind: Kind.pri, onTap: () {
              widget.onTodo();
              return true;
            }),
          ],
        ));
  }

  @override
  void dispose() {
    _chips.dispose();
    _q.dispose();
    super.dispose();
  }

  /// Peeks the chip row sideways once so people notice it scrolls.
  Future<void> _nudge() async {
    if (!mounted || !_chips.hasClients || MediaQuery.of(context).disableAnimations) return;
    final max = _chips.position.maxScrollExtent;
    if (max <= 0) return;
    await _chips.animateTo(max < 90 ? max : 90, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted && _chips.hasClients) {
      await _chips.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    }
  }

  void _setFilter(String f) {
    setState(() => LibUi.f = f);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chipKeys[f]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: .5, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    });
  }

  bool _vis(Item b) {
    if (home) return true;
    final f = LibUi.f, q = LibUi.q.toLowerCase();
    if (b.isDecor) return f == 'all' && q.isEmpty;
    final fOk = f == 'all' || b.status == f || (f.startsWith('h:') && b.tags.contains(f.substring(2)));
    return fOk && (q.isEmpty || '${b.title} ${b.author}'.toLowerCase().contains(q));
  }

  bool get _filtered => !home && (LibUi.f != 'all' || LibUi.q.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final top = MediaQuery.paddingOf(context).top;
        final all = store.allBooks.toList();
        return Stack(children: [
          ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(0, top + 26, 0, 170),
            children: [
              _header(all.length),
              if (home && store.isSample) _sampleLibraryBanner(),
              if (home) _homeBar(),
              if (!home) ...[
                _search(),
                _chipsRow(all),
                _lbar(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 2, 22, 0),
                  child: Text('Tip: press and hold a book or decoration, then drag to reorder it. Use the slider under a shelf to see every book.',
                      style: nu(12, FontWeight.w600, C.muted, 1.35)),
                ),
              ],
              ..._shelves(),
            ],
          ),
          if (!home)
            Positioned(
              right: 20,
              bottom: 104 + MediaQuery.paddingOf(context).bottom,
              child: Semantics(
                button: true,
                label: 'Add a book',
                child: Pressable(
                  onTap: () => openAddBook(),
                  scale: .9,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: C.brown,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color.fromRGBO(120, 60, 10, .35), offset: Offset(0, 4), blurRadius: 12)],
                    ),
                    alignment: Alignment.center,
                    child: const SvgIcon(Ic.plus, color: Colors.white, size: 26, stroke: 2.6),
                  ),
                ),
              ),
            ),
        ]);
      },
    );
  }

  Widget _sampleLibraryBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          const Text('📚', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sample Library Active', style: nu(13.5, FontWeight.w800, C.brown)),
                Text('Tap Logout to enter your actual empty library',
                    style: nu(11.5, FontWeight.w600, C.muted)),
              ],
            ),
          ),
          Pressable(
            onTap: _confirmLogout,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: C.brown,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.logout_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text('Logout', style: nu(12, FontWeight.w800, Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout() {
    Buzz.tick();
    openDialog((ctx) => AppDialog(
          title: 'Log out of sample library?',
          children: [
            const Sub(
              'You will return to the welcome screen where you can start without the sample library and begin building your actual personal library.',
            ),
          ],
          actions: [
            const Btn('Cancel'),
            Btn('Logout', kind: Kind.pri, onTap: () {
              store.logout();
              toast('Logged out');
              return true;
            }),
          ],
        ));
  }

  Widget _header(int total) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            H1(home ? 'Home' : 'My Library'),
            const SizedBox(height: 2),
            Text(home ? '${_greeting()}, ${store.profile.first} · ${plural(total, 'book')}' : plural(total, 'book'),
                style: nu(14, FontWeight.w600, C.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (home) ...[
            Builder(
              builder: (ctx) => BadgeButton(
                icon: Ic.share,
                count: 0,
                label: 'Share',
                onTap: () => openBookShareSheet(ctx, initialTab: 0),
              ),
            ),
            const SizedBox(width: 10),
          ],
          const BellButton(),
          const SizedBox(width: 10),
          BadgeButton(icon: Ic.gift, count: store.unclaimed.length, label: 'Rewards', onTap: () => openRewards()),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Profile',
            child: Pressable(onTap: widget.onProfile, scale: .9, child: const MeAvatar(size: 50)),
          ),
        ]),
      ]),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 5 ? 'Up late' : h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
  }

  Widget _homeBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text('Your shelves', style: nu(17, FontWeight.w800))),
          Semantics(
            button: true,
            label: 'View every shelf full screen',
            child: Pressable(
              onTap: () => openFullShelf(),
              scale: .9,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: C.dark ? C.chip : const Color(0xFFE5F1F6), borderRadius: BorderRadius.circular(16)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SvgIcon(Ic.fullscreen, color: C.dark ? C.chipText : const Color(0xFF1F6F8B), size: 16, stroke: 2.2),
                  const SizedBox(width: 6),
                  Text('Full view', style: nu(13, FontWeight.w800, C.dark ? C.chipText : const Color(0xFF1F6F8B))),
                ]),
              ),
            ),
          ),
        ]),
        const UpdateCard(),
        if (store.goalThisYear > 0) ...[
          const SizedBox(height: 12),
          _GoalCard(onTap: widget.onStats),
        ],
        if (_lastRead() case final b?) ...[
          const SizedBox(height: 12),
          _ContinueCard(b),
        ],
      ]),
    );
  }

  Item? _lastRead() {
    // Only reading books appear in continue reading, finished books are excluded
    final r = store.allBooks
        .where((b) => b.readAt != null && store.copyExists(b) && !b.finished)
        .toList()
      ..sort((a, b) => b.readAt!.compareTo(a.readAt!));
    return r.isEmpty ? null : r.first;
  }


  Widget _search() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
        child: TextField(
          controller: _q,
          onChanged: (v) => setState(() => LibUi.q = v.trim()),
          textInputAction: TextInputAction.search,
          style: nu(15, FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Search title or author',
            hintStyle: nu(15, FontWeight.w600, C.hint),
            isDense: true,
            filled: true,
            fillColor: C.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            suffixIcon: LibUi.q.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close_rounded, color: C.muted, size: 20),
                    onPressed: () {
                      _q.clear();
                      setState(() => LibUi.q = '');
                    },
                  ),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: C.inputLine)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: C.brown, width: 2)),
          ),
        ),
      );

  Widget _chipsRow(List<Item> all) {
    int n(bool Function(Item) t) => all.where(t).length;
    final chips = <(String, String)>[
      ('all', 'All (${all.length})'),
      ('r', 'Reading (${n((b) => b.status == 'r')})'),
      ('f', 'Finished (${n((b) => b.status == 'f')})'),
      for (final h in store.headings) ('h:$h', '$h (${n((b) => b.tags.contains(h))})'),
    ];
    return SizedBox(
      height: 66,
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, .9, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: ListView(
          controller: _chips,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(22, 18, 52, 0),
          children: [
            for (final c in chips)
              Padding(
                key: _chipKeys.putIfAbsent(c.$1, GlobalKey.new),
                padding: const EdgeInsets.only(right: 10),
                child: Center(child: PopChip(
                  c.$2,
                  on: LibUi.f == c.$1,
                  onTap: () => _setFilter(c.$1),
                  onLongPress: c.$1.startsWith('h:') ? () => _editHeading(c.$1.substring(2)) : null,
                )),
              ),
            Center(child: PopChip('＋ Heading', on: false, dashed: true, onTap: _newHeading)),
          ],
        ),
      ),
    );
  }

  Widget _lbar() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
        child: Row(children: [
          Pressable(
            onTap: _newCollection,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('+ New Collection', style: nu(14, FontWeight.w700, C.brown)),
            ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            toggled: LibUi.exp,
            label: 'Show all books in grid',
            child: Pressable(
              onTap: () {
                setState(() => LibUi.exp = !LibUi.exp);
                toast(LibUi.exp ? 'Showing every book' : 'Shelf view');
              },
              scale: .9,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LibUi.exp ? C.brown : C.card,
                  border: Border.all(color: LibUi.exp ? C.brown : C.inputLine),
                ),
                alignment: Alignment.center,
                child: SvgIcon(Ic.expand, color: LibUi.exp ? Colors.white : C.ink, size: 22),
              ),
            ),
          ),
        ]),
      );

  List<Widget> _shelves() {
    final filtered = _filtered;
    final out = <Widget>[];
    for (final (ci, c) in store.cols.indexed) {
      final mn = c.items.where((i) => !i.sub && _vis(i)).toList();
      final sb = c.items.where((i) => i.sub && _vis(i)).toList();
      final subAll = c.items.where((i) => i.sub).length;
      final subN = store.bookCount(c, true), mainN = store.bookCount(c, false);
      if (mn.isEmpty && sb.isEmpty && (filtered || home && c.items.isEmpty && store.cols.length > 1)) continue;
      final show = c.subOn && (c.subOpen || (filtered && sb.isNotEmpty));
      out.add(Padding(
        key: ValueKey(c.id),
        padding: const EdgeInsets.only(top: 14),
        child: Column(children: [
          if (mn.isNotEmpty || !filtered)
            ShelfRow(
              key: ValueKey('${c.id}-main'),
              col: c,
              palette: ci,
              items: mn,
              count: filtered ? mn.where((i) => !i.isDecor).length : mainN,
              filtered: filtered,
              home: home,
              exp: LibUi.exp && !home,
              onOpen: (it) => _open(c, it),
              onMore: () => _more(c),
              onAdd: () => _add(c, false),
              onDecor: () => _addDecor(c, false),
            ),
          if (home ? (subAll > 0 || c.subOn) : (mainN >= shelfMax || c.subOn))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _SubButton(
                label: c.subOn ? (show ? 'Hide shelf' : 'Show sub shelf${subN > 0 ? ' ($subN)' : ''}') : '＋ Sub shelf',
                open: show,
                onTap: () {
                  if (!c.subOn) {
                    c.subOn = true;
                    c.subOpen = true;
                    toast('Sub shelf added below');
                  } else {
                    c.subOpen = !c.subOpen;
                  }
                  store.changed();
                },
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: ease,
            alignment: Alignment.topCenter,
            child: show
                ? FadeIn(
                    key: ValueKey('${c.id}-subs'),
                    dy: -10,
                    ms: 350,
                    child: Padding(
                    padding: const EdgeInsets.only(top: 22),
                    child: ShelfRow(
                      key: ValueKey('${c.id}-sub'),
                      col: c,
                      palette: ci,
                      items: sb,
                      sub: true,
                      count: filtered ? sb.where((i) => !i.isDecor).length : subN,
                      filtered: filtered,
                      home: home,
                      exp: LibUi.exp && !home,
                      onOpen: (it) => _open(c, it),
                      onAdd: () => _add(c, true),
                      onDecor: () => _addDecor(c, true),
                    ),
                  ))
                : const SizedBox(width: double.infinity, key: ValueKey('none')),
          ),
        ]),
      ));
    }
    if (out.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(22, 48, 22, 0),
        child: Text(
          store.cols.isEmpty
              ? 'No shelves yet. Tap “+ New Collection” to build your first one.'
              : LibUi.f.startsWith('h:')
                  ? 'No books under this heading yet. Tap a book to add it.'
                  : 'No books match. Try another filter or search.',
          textAlign: TextAlign.center,
          style: nu(15, FontWeight.w600, C.muted),
        ),
      ));
    }
    return out;
  }

  // ---------------- actions ----------------

  void _open(Collection c, Item it) {
    Sfx.play('tap');
    if (it.isDecor) {
      openDecor(c, it, home: home);
    } else if (home) {
      openBookView(c, it);
    } else {
      _bookMenu(c, it);
    }
  }

  void _add(Collection c, bool sub) {
    final cn = store.bookCount(c, sub);
    if (cn >= shelfMax) {
      toast(sub
          ? 'Sub shelf is full (10 books)'
          : c.subOn
              ? 'Shelf is full (10 books). Add to the sub shelf below'
              : 'Shelf is full (10 books). Tap ＋ Sub shelf to keep adding');
      return;
    }
    openAddBook(col: c, sub: sub);
  }

  void _addDecor(Collection c, bool sub) {
    final n = store.rowCount(c, sub);
    final isFull = n >= shelfMax;
    final free = shelfMax - n;
    final hasAnyLights = store.cols.any((col) => col.mainLights != null || col.subLights != null);
    final curLights = c.lights(sub: sub);
    String noteSize = 'm';

    openDialog((ctx) => StatefulBuilder(
          builder: (ctx, set) {
            return AppDialog(
              title: 'Decorate this ${sub ? 'sub shelf' : 'shelf'}',
              maxWidth: 400,
              children: [
                Sub(isFull
                    ? 'The 10 object spots are full, but you can still add stickers and lights.'
                  : '${plural(free, 'free spot')} for objects. Adding a book to a full shelf replaces the last object.'),
              const SizedBox(height: 8),

              // --- Hanging lights ---
              Row(children: [
                Text('Hanging lights', style: nu(13, FontWeight.w800, C.chipText)),
                if (curLights != null) ...[
                  const SizedBox(width: 8),
                  Text('(${curLights == 'multi' ? 'Multicolor' : 'Warm white'})', style: nu(12, FontWeight.w700, C.brown)),
                ],
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Pressable(
                  onTap: () {
                    store.setLights(c, 'warm', sub: sub);
                    Sfx.play('pop');
                    toast('Warm white lights hung on ${c.name}${sub ? ' · sub shelf' : ''}');
                    set(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: curLights == 'warm' ? C.brown.withValues(alpha: .18) : C.field,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: curLights == 'warm' ? C.brown : C.inputLine, width: curLights == 'warm' ? 2 : 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('💡', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text('Warm white', style: nu(12.5, FontWeight.w800, curLights == 'warm' ? C.brown : C.ink)),
                    ]),
                  ),
                ),
                Pressable(
                  onTap: () {
                    store.setLights(c, 'multi', sub: sub);
                    Sfx.play('pop');
                    toast('Multicolor lights hung on ${c.name}${sub ? ' · sub shelf' : ''}');
                    set(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: curLights == 'multi' ? C.brown.withValues(alpha: .18) : C.field,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: curLights == 'multi' ? C.brown : C.inputLine, width: curLights == 'multi' ? 2 : 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('🌈', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text('Multicolor', style: nu(12.5, FontWeight.w800, curLights == 'multi' ? C.brown : C.ink)),
                    ]),
                  ),
                ),
                if (curLights != null)
                  Pressable(
                    onTap: () {
                      store.setLights(c, null, sub: sub);
                      Sfx.play('swoosh');
                      toast('Lights removed from this shelf');
                      set(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: C.field,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: C.inputLine),
                      ),
                      child: Text('Remove here', style: nu(12, FontWeight.w700, C.muted)),
                    ),
                  ),
                if (hasAnyLights)
                  Pressable(
                    onTap: () {
                      store.setLights(c, null, sub: sub, all: true);
                      Sfx.play('swoosh');
                      toast('Lights removed from all shelves');
                      set(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: C.field,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: C.inputLine),
                      ),
                      child: Text('Remove all', style: nu(12, FontWeight.w700, C.dangerInk)),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),

              // --- Objects ---
              Row(children: [
                Text('Objects', style: nu(13, FontWeight.w800, C.chipText)),
                const SizedBox(width: 8),
                Text(isFull ? '(full)' : '($free spots left)', style: nu(12, FontWeight.w600, C.muted)),
              ]),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .32),
                child: GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: .78,
                  children: [
                    for (final g in gadgets.values)
                      Semantics(
                        button: true,
                        label: g.name,
                        child: Pressable(
                          onTap: () {
                            if (isFull) {
                              toast('This shelf is full (10 spots)');
                              return;
                            }
                            Navigator.pop(ctx);
                            if (store.addDecor(c, g.key, sub: sub)) {
                              Sfx.play('pop');
                              toast('${g.name} added to ${c.name}${sub ? ' · sub shelf' : ''}');
                            }
                          },
                          child: Opacity(
                            opacity: isFull ? .45 : 1.0,
                            child: Container(
                              decoration: BoxDecoration(
                                  color: C.field, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.inputLine)),
                              padding: const EdgeInsets.fromLTRB(2, 6, 2, 5),
                              child: Column(children: [
                                Expanded(child: SvgPicture.string(g.svg, fit: BoxFit.contain)),
                                const SizedBox(height: 4),
                                Text(g.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(10, FontWeight.w700)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Stickers ---
              Row(children: [
                Text('Stickers', style: nu(13, FontWeight.w800, C.chipText)),
                const SizedBox(width: 8),
                Text('${c.stickersFor(sub: sub).length}/12', style: nu(12, FontWeight.w600, C.muted)),
              ]),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: .88,
                children: [
                  for (final st in shelfStickers.values)
                    Semantics(
                      button: true,
                      label: '${st.name} sticker',
                      child: Pressable(
                        onTap: () {
                          if (c.stickersFor(sub: sub).length >= 12) {
                            toast('That shelf already has 12 stickers');
                            return;
                          }
                          Navigator.pop(ctx);
                          if (store.addSticker(c, st.key, sub: sub)) {
                            Sfx.play('pop');
                            toast('${st.name} sticker added. Tap it on your shelf to tear or remove');
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                              color: C.field, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.inputLine)),
                          padding: const EdgeInsets.all(6),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            SizedBox(width: 38, height: 38, child: SvgPicture.string(st.svg)),
                            const SizedBox(height: 4),
                            Text(st.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(10, FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // --- Sticky Notes ---
              Row(children: [
                Text('Sticky notes', style: nu(13, FontWeight.w800, C.chipText)),
                const SizedBox(width: 8),
                Text('${c.notesFor(sub: sub).length}/10', style: nu(12, FontWeight.w600, C.muted)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                for (final (sz, label) in const [('s', 'S Small'), ('m', 'M Medium'), ('l', 'L Large')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => set(() => noteSize = sz),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: noteSize == sz ? C.brown : C.chip,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: noteSize == sz ? C.brown : const Color(0x33000000),
                            width: noteSize == sz ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          label,
                          style: nu(12, FontWeight.w800, noteSize == sz ? Colors.white : C.chipText),
                        ),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 8, children: [
                for (final entry in stickyColorDefs.entries)
                  Pressable(
                    onTap: () {
                      if (c.notesFor(sub: sub).length >= 10) {
                        toast('That shelf already has 10 sticky notes');
                        return;
                      }
                      Navigator.pop(ctx);
                      if (store.addStickyNote(c, text: 'Reading note…', color: entry.key, ink: '#1c2f6b', sub: sub, size: noteSize)) {
                        Sfx.play('pop');
                        toast('Sticky note pinned to shelf! Tap it on the shelf to write or edit.');
                      }
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: entry.value,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x33000000)),
                        boxShadow: const [BoxShadow(color: Color(0x18000000), offset: Offset(1, 2), blurRadius: 3)],
                      ),
                      alignment: Alignment.center,
                      child: const Text('📝', style: TextStyle(fontSize: 20)),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),

              // --- Music CD (Compact Disc) ---
              Row(children: [
                Text('Music CD 💿', style: nu(13, FontWeight.w800, C.chipText)),
                const SizedBox(width: 8),
                Text(c.cdFor(sub: sub) != null ? '1/1 added' : '0/1 (Max 1 per shelf)', style: nu(12, FontWeight.w600, C.muted)),
              ]),
              const SizedBox(height: 8),
              if (c.cdFor(sub: sub) != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: C.field,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: C.inputLine),
                  ),
                  child: Row(
                    children: [
                      const Text('💿', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.cdFor(sub: sub)!.title?.isNotEmpty == true
                                  ? c.cdFor(sub: sub)!.title!
                                  : 'CD on shelf (no song yet)',
                              style: nu(13, FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Tap the CD directly on the shelf to upload MP3 or manage',
                              style: nu(11, FontWeight.w600, C.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Pressable(
                        onTap: () {
                          Navigator.pop(ctx);
                          store.removeCd(c, sub: sub);
                          toast('CD removed & song deleted');
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0x18FF0000),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Pressable(
                  onTap: () {
                    Navigator.pop(ctx);
                    if (store.addCd(c, sub: sub)) {
                      Sfx.play('pop');
                      toast('CD placed on shelf! 💿 Tap it to upload your MP3 song.');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: C.field,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.inputLine),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(
                              colors: [
                                Color(0xFFE8EEF5),
                                Color(0xFFC7D7E8),
                                Color(0xFFFFD5E5),
                                Color(0xFFD6F5E3),
                                Color(0xFFFFF2C2),
                                Color(0xFFE8EEF5),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 2))
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Text('💿', style: TextStyle(fontSize: 20)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Add Music CD to Shelf', style: nu(13.5, FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text('Upload an MP3 song to play on Home (rotates while playing!)', style: nu(11.5, FontWeight.w600, C.muted)),
                            ],
                          ),
                        ),
                        Icon(Icons.add_circle, color: C.brown, size: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ],
            actions: const [Btn('Close')],
          );
        }));
  }

  void _bookMenu(Collection c, Item b) {
    const status = {'r': 'Reading', 'f': 'Finished'};
    Future<void> pickCover() async {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 700, imageQuality: 85);
      if (x == null) return;
      b.cover = await store.saveImage(await x.readAsBytes());
      store.changed();
      toast('Cover updated');
    }

    openDialog((ctx) => ListenableBuilder(
          listenable: store,
          builder: (ctx, _) => AppDialog(
            title: b.title,
            children: [
              if (c.name.trim().toLowerCase() == 'shared books' || (b.fromUser != null && b.fromUser!.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8DC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD4B996)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🤝 ', style: TextStyle(fontSize: 15)),
                        Text(
                          'Book from ${b.fromUser?.trim().isNotEmpty == true ? b.fromUser : "User 2"}',
                          style: nu(13, FontWeight.w800, C.brown),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(children: [
                _Shadowed(child: BookCover(b, w: 68, h: 96, titleSize: 9, authorSize: 7, titleLines: 5)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${b.author} · ${status[b.status]}', style: nu(14, FontWeight.w600, C.muted)),
                    const SizedBox(height: 4),
                    StarRating(
                      value: b.rating,
                      size: 22,
                      onChanged: (v) {
                        b.rating = v;
                        store.changed();
                      },
                    ),
                    const SizedBox(height: 6),
                    Pill(b.cover == null ? 'Upload cover' : 'Change cover',
                        kind: Kind.pri, size: 13, pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), onTap: pickCover),
                  ]),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Text(b.desc.isEmpty ? 'No description yet.' : b.desc, style: nu(14, FontWeight.w600, C.body, 1.5)),
              ),
              CopyPanel(b),
            ],
            actions: [
              Btn.icon(SvgIcon(Ic.read, color: b.status == 'r' ? Colors.white : C.ink),
                  tip: 'Reading', kind: b.status == 'r' ? Kind.pri : Kind.normal, onTap: () => _setStatus(b, 'r')),
              Btn.icon(SvgIcon(Ic.done, color: b.status == 'f' ? Colors.white : C.ink, stroke: 2.2),
                  tip: 'Finished', kind: b.status == 'f' ? Kind.pri : Kind.normal, onTap: () => _setStatus(b, 'f')),
              if (store.cols.length > 1) Btn.icon(SvgIcon(Ic.move, color: C.ink), tip: 'Move to…', then: () => _moveMenu(b)),
              Btn.icon(SvgIcon(Ic.edit, color: C.ink), tip: b.desc.isEmpty ? 'Add description' : 'Edit description', then: () => _editDesc(b)),
              if (b.cover != null)
                Btn.icon(SvgIcon(Ic.noImg, color: C.ink), tip: 'Remove cover', onTap: () {
                  b.cover = null;
                  store.changed();
                  toast('Cover removed');
                  return true;
                }),
              Btn.icon(SvgIcon(Ic.trash, color: C.dangerInk), tip: 'Delete book', kind: Kind.dng, then: () => openTear(b)),
              for (final (i, h) in store.headings.indexed)
                Btn(b.tags.contains(h) ? '✓ $h' : '+ $h', breakBefore: i == 0, small: true, onTap: () {
                  final on = b.tags.contains(h);
                  on ? b.tags.remove(h) : b.tags.add(h);
                  store.changed();
                  toast(on ? 'Removed from $h' : 'Added to $h');
                  return true;
                }),
            ],
          ),
        ));
  }

  bool _setStatus(Item b, String s) {
    final wasDone = b.finished;
    store.setStatus(b, s);
    toast('Marked as ${s == 'f' ? 'Finished' : 'Reading'}');
    if (s == 'f' && !wasDone) {
      Sfx.play('check');
      final size = MediaQuery.sizeOf(context);
      confetti(Offset(size.width / 2, size.height * .45), count: 36);
      if (b.rating == 0) Future.delayed(const Duration(milliseconds: 650), () => askRating(b));
    }
    return true;
  }

  void _moveMenu(Item b) {
    final from = store.colOf(b);
    openDialog((ctx) => AppDialog(
          title: 'Move “${b.title}” to…',
          children: [
            const Sub('Pick the shelf this book should go to.'),
            for (final c in store.cols.where((c) => c != from))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Builder(builder: (_) {
                  final full = store.placeFor(c) == null;
                  return Pill('${c.emoji} ${c.name}${full ? ' (full)' : ''}',
                      expand: true,
                      kind: full ? Kind.ghost : Kind.normal,
                      onTap: () {
                        if (full) {
                          toast('“${c.name}” is full');
                          return;
                        }
                        Navigator.pop(ctx);
                        store.moveBook(b, c);
                        Sfx.play('swoosh');
                        toast('Moved to ${c.name}${b.sub ? ' · sub shelf' : ''}');
                      });
                }),
              ),
          ],
          actions: const [Btn('Cancel')],
        ));
  }

  void _editDesc(Item b) {
    final t = TextEditingController(text: b.desc);
    openDialog((ctx) => AppDialog(title: 'About this book', children: [
          AppInput(t, 'What is this book about?', maxLength: 240, lines: 4, autofocus: true),
        ], actions: [
          const Btn('Cancel'),
          Btn('Save', kind: Kind.pri, onTap: () {
            b.desc = t.text.trim();
            store.changed();
            toast('Description saved');
            return true;
          }),
        ]));
  }

  void _more(Collection c) {
    final n = c.books.length;
    openDialog((_) => AppDialog(title: c.name, children: [
          Sub('${plural(n, 'book')} in this collection'),
        ], actions: [
          Btn('Rename', then: () => editCollection(c)),
          Btn('Remove entire shelf', kind: Kind.dng, then: () async {
            final ok = await confirm('Remove “${c.name}”?',
                'This removes the whole shelf, including its ${plural(n, 'book')} and decorations. This can’t be undone.',
                yes: 'Remove shelf');
            if (!ok) return;
            store.cols.remove(c);
            store.changed();
            Sfx.play('swoosh');
            toast('Shelf removed');
          }),
          const Btn('Close'),
        ]));
  }

  void _newCollection() => editCollection(null);

  void _newHeading() {
    final t = TextEditingController();
    var err = '';
    openDialog((ctx) => StatefulBuilder(
          builder: (ctx, set) => AppDialog(title: 'New heading', children: [
            const Sub('Create a tab for your own list, like Favourites or 2026 reads.'),
            AppInput(t, 'Heading', maxLength: 20, autofocus: true),
            ErrText(err),
          ], actions: [
            const Btn('Cancel'),
            Btn('Create', kind: Kind.pri, onTap: () {
              final v = t.text.trim();
              if (v.isEmpty || store.headings.contains(v) || ['all', 'reading', 'finished'].contains(v.toLowerCase())) {
                set(() => err = v.isEmpty ? 'Give it a name.' : 'You already have that one.');
                return false;
              }
              store.headings.add(v);
              store.changed();
              _setFilter('h:$v');
              toast('Heading added. Tap a book to put it here.');
              return true;
            }),
          ]),
        ));
  }

  void _editHeading(String h) {
    final t = TextEditingController(text: h);
    openDialog((ctx) => AppDialog(title: 'Edit heading', children: [
          AppInput(t, 'Heading', maxLength: 20),
        ], actions: [
          Btn('Delete', kind: Kind.dng, onTap: () {
            store.headings.remove(h);
            for (final b in store.allBooks) {
              b.tags.remove(h);
            }
            if (LibUi.f == 'h:$h') LibUi.f = 'all';
            store.changed();
            toast('Heading deleted');
            return true;
          }),
          const Btn('Cancel'),
          Btn('Save', kind: Kind.pri, onTap: () {
            final v = t.text.trim();
            if (v.isEmpty || (v != h && store.headings.contains(v))) return false;
            store.headings[store.headings.indexOf(h)] = v;
            for (final b in store.allBooks) {
              final i = b.tags.indexOf(h);
              if (i >= 0) b.tags[i] = v;
            }
            if (LibUi.f == 'h:$h') LibUi.f = 'h:$v';
            store.changed();
            return true;
          }),
        ]));
  }
}

class _SubButton extends StatelessWidget {
  final String label;
  final bool open;
  final VoidCallback onTap;
  const _SubButton({required this.label, required this.open, required this.onTap});
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: open ? Colors.transparent : C.chip,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: open ? const Color(0xFFD6C3A5) : C.chip, width: 1.5),
          ),
          child: Text(label, style: nu(13, FontWeight.w700, C.chipText)),
        ),
      );
}

class _Shadowed extends StatelessWidget {
  final Widget child;
  const _Shadowed({required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .2), offset: Offset(0, 2), blurRadius: 6)],
        ),
        child: child,
      );
}

/// This year's reading goal, as a progress ring.
class _GoalCard extends StatelessWidget {
  final VoidCallback onTap;
  const _GoalCard({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final done = store.finishedThisYear, goal = store.goalThisYear;
    final p = (done / goal).clamp(0.0, 1.0);
    return Pressable(
      onTap: onTap,
      scale: .98,
      child: CardBox(
        pad: const EdgeInsets.all(12),
        child: Row(children: [
          SizedBox(
            width: 46,
            height: 46,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: p),
              duration: const Duration(milliseconds: 900),
              curve: ease,
              builder: (_, v, _) => CircularProgressIndicator(value: v, strokeWidth: 6, color: C.brown, backgroundColor: C.chip, strokeCap: StrokeCap.round),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🎯 ${DateTime.now().year} reading goal', style: nu(12, FontWeight.w800, C.brown)),
              Text(done >= goal ? 'Goal reached: $done of $goal books!' : '$done of $goal books', style: nu(15, FontWeight.w800)),
              Text(done >= goal ? 'Everything from here is a bonus.' : '${goal - done} to go · ${(p * 100).round()}%',
                  style: nu(12, FontWeight.w700, C.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// "How was it?" after finishing a book.
void askRating(Item b) {
  var r = b.rating;
  openDialog((ctx) => StatefulBuilder(
        builder: (ctx, set) => AppDialog(title: 'How was it?', children: [
          Sub('You finished ${b.title}. Give it a rating?'),
          Center(
            child: StarRating(
              value: r,
              size: 40,
              onChanged: (v) {
                set(() => r = v);
                b.rating = v;
                store.changed();
                if (v > 0) {
                  Future.delayed(const Duration(milliseconds: 550), () {
                    if (ctx.mounted && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                    toast('Rated $v ★');
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 6),
        ], actions: const [
          Btn('Skip'),
        ]),
      ));
}

/// "Continue reading" on Home: the PDF you opened last.
class _ContinueCard extends StatelessWidget {
  final Item b;
  const _ContinueCard(this.b);
  @override
  Widget build(BuildContext context) {
    final pct = b.pages <= 1 ? 0.0 : (b.page / (b.pages - 1)).clamp(0.0, 1.0);
    return Pressable(
      onTap: () => openReader(b),
      scale: .98,
      child: CardBox(
        pad: const EdgeInsets.all(12),
        child: Row(children: [
          _Shadowed(child: BookCover(b, w: 46, h: 64, titleSize: 7, authorSize: 5)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('📖 Continue reading', style: nu(12, FontWeight.w800, C.brown)),
              Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(15, FontWeight.w800)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: pct, minHeight: 5, color: C.brown, backgroundColor: C.chip),
              ),
              const SizedBox(height: 4),
              Text('Page ${b.page + 1} of ${b.pages} · ${(pct * 100).round()}%', style: nu(11.5, FontWeight.w700, C.muted)),
            ]),
          ),
          const SizedBox(width: 10),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: C.brown, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
          ),
        ]),
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// Shared dialogs (also used by the profile and full-screen shelf)
// ---------------------------------------------------------------------------

/// Read-only look at a book (Home mode and profile).
void openBookView(Collection c, Item b) {
  openDialog((_) => AppDialog(title: b.title, children: [
        if (c.name.trim().toLowerCase() == 'shared books' || (b.fromUser != null && b.fromUser!.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8DC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD4B996)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🤝 ', style: TextStyle(fontSize: 15)),
                  Text(
                    'Book from ${b.fromUser?.trim().isNotEmpty == true ? b.fromUser : "User 2"}',
                    style: nu(13, FontWeight.w800, C.brown),
                  ),
                ],
              ),
            ),
          ),
        Row(children: [
          _Shadowed(child: BookCover(b, w: 68, h: 96, titleSize: 9, authorSize: 7, titleLines: 5)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.author, style: nu(14, FontWeight.w600, C.muted)),
              if (b.rating > 0) ...[const SizedBox(height: 4), StarRating(value: b.rating, size: 18)],
              const SizedBox(height: 6),
              Text('${b.finished ? 'Finished' : 'Reading'} · ${c.emoji} ${c.name}', style: nu(13, FontWeight.w600, C.muted)),
              if (b.finishedAt != null) Text('Finished ${fmtDate(b.finishedAt!)}', style: nu(12, FontWeight.w600, C.muted)),
            ]),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(b.desc.isEmpty ? 'No description yet.' : b.desc, style: nu(14, FontWeight.w600, C.body, 1.5)),
        ),
        CopyPanel(b, editable: false),
      ], actions: const [
        Btn('Close'),
      ]));
}

/// Tear a book out of the library (delete), with "Tape it back" undo.
void openTear(Item b) {
  final key = GlobalKey<TearCoverState>();
  var torn = false;
  (Collection, int, Item)? undo;
  openDialog((ctx) => StatefulBuilder(builder: (ctx, set) {
        final pal = coverFor(b.title);
        if (torn) {
          return AppDialog(clip: Clip.none, children: [
            TornMessage(
              emoji: '📖💥',
              title: 'You tore out ${b.title}',
              body: 'It’s gone from your shelf. Changed your mind? Tape it back.',
            ),
          ], actions: [
            Btn('Tape it back', kind: Kind.pri, onTap: () {
              if (undo != null) store.restoreItem(undo!);
              Sfx.play('tape');
              toast('Taped back together');
              return true;
            }),
            const Btn('Close'),
          ]);
        }
        return AppDialog(title: 'Delete this book?', clip: Clip.none, children: [
          Sub('${b.title} · ${b.author}', pad: EdgeInsets.zero),
          Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
              child: DecoratedBox(
                decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color.fromRGBO(40, 20, 5, .35), offset: Offset(0, 10), blurRadius: 18)]),
                child: TearCover(
                  key: key,
                  w: 124,
                  h: 176,
                  paper: pal[0],
                  face: CoverFace(title: b.title, author: b.author, image: b.cover, w: 124, h: 176, titleSize: 15, authorSize: 11, titleLines: 5, topBorder: 6, spine: 8),
                  pieceFace: () => CoverFace(title: b.title, author: b.author, image: b.cover, w: 124, h: 176, titleSize: 15, authorSize: 11, titleLines: 5, topBorder: 6, spine: 8),
                  onTorn: () {
                    undo = store.removeItem(b);
                    set(() => torn = true);
                  },
                ),
              ),
            ),
          ),
          Text('Feeling dramatic? Slide across the book to tear it out.',
              textAlign: TextAlign.center, style: nu(13, FontWeight.w700, C.muted)),
        ], actions: [
          const Btn('Keep it'),
          Btn('Delete', kind: Kind.dng, onTap: () {
            key.currentState?.tear();
            return false;
          }),
        ]);
      }));
}

/// A decoration up close: tap to play, slide to smash (removes it, with undo).
void openDecor(Collection c, Item it, {required bool home}) {
  final key = GlobalKey<DecorStageState>();
  final name = gadgetName(it.gadget!);
  var gone = false;
  (Collection, int, Item)? undo;
  openDialog((ctx) => StatefulBuilder(builder: (ctx, set) {
        if (gone) {
          return AppDialog(clip: Clip.none, children: [
            TornMessage(emoji: '💥', title: 'You broke your ${name.toLowerCase()}', body: 'It’s in pieces and off the shelf. Want to glue it back?'),
          ], actions: [
            Btn('Glue it back', kind: Kind.pri, onTap: () {
              if (undo != null) store.restoreItem(undo!);
              Sfx.play('tape');
              toast('Glued back together');
              return true;
            }),
            const Btn('Close'),
          ]);
        }
        return AppDialog(
          title: name,
          clip: Clip.none,
          children: [
            Sub('A decoration on your ${c.emoji} ${c.name} shelf', pad: EdgeInsets.zero),
            Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                child: DecorStage(
                  key: key,
                  kind: it.gadget!,
                  lit: it.lit,
                  onLit: (v) {
                    it.lit = v;
                    store.changed();
                  },
                  onSmashed: home
                      ? null
                      : () {
                          undo = store.removeItem(it);
                          set(() => gone = true);
                        },
                ),
              ),
            ),
            Text(
              '${decorHint[it.gadget] ?? 'Tap it to play with it.'}${home ? '' : ' Slide across it to smash it.'}',
              textAlign: TextAlign.center,
              style: nu(13, FontWeight.w700, C.muted),
            ),
          ],
          actions: home
              ? const [Btn('Close')]
              : [
                  Btn('Remove', kind: Kind.dng, onTap: () {
                    key.currentState?.smash();
                    return false;
                  }),
                  const Btn('Close'),
                ],
        );
      }));
}

const _emojis = ['📚', '📖', '⭐', '🔖', '❤️', '🐉', '🔍', '🏛️', '🧠', '☕', '🌊', '💻', '🎧', '🌙', '🌿', '🚀', '👻', '🧸'];

/// Create (c == null) or rename a collection.
void editCollection(Collection? c) {
  final t = TextEditingController(text: c?.name ?? '');
  var emoji = c?.emoji ?? '📚';
  openDialog((ctx) => StatefulBuilder(
        builder: (ctx, set) => AppDialog(title: c == null ? 'New collection' : 'Rename collection', children: [
          AppInput(t, 'Collection name', maxLength: 28, autofocus: c == null),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in _emojis)
              Pressable(
                onTap: () => set(() => emoji = e),
                scale: .85,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: emoji == e ? C.brown.withValues(alpha: .18) : C.chip,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: emoji == e ? C.brown : Colors.transparent, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(e, style: const TextStyle(fontSize: 19)),
                ),
              ),
          ]),
        ], actions: [
          const Btn('Cancel'),
          Btn(c == null ? 'Create' : 'Save', kind: Kind.pri, onTap: () {
            final v = t.text.trim();
            if (v.isEmpty) return false;
            if (c == null) {
              store.cols.add(Collection(name: v, emoji: emoji));
              toast('Created “$v”');
              Sfx.play('pop');
            } else {
              c.name = v;
              c.emoji = emoji;
            }
            store.changed();
            return true;
          }),
        ]),
      ));
}

/// The gift box: claim earned rewards with confetti, or see what's next.
void openRewards() {
  final r = store.unclaimed.isEmpty ? null : store.unclaimed.first;
  if (r == null) {
    final next = store.nextReward;
    openDialog((_) => AppDialog(title: '🎁 Rewards', children: [
          if (next == null)
            const Sub('You’ve unlocked every reward. Legendary!')
          else ...[
            Sub('Next up: ${next.emoji} ${next.title}. ${next.desc}'),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (next.value(store) / next.goal).clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 900),
                curve: ease,
                builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 10, color: C.brown, backgroundColor: C.chip),
              ),
            ),
            const SizedBox(height: 6),
            Text('${next.value(store)} / ${next.goal}', style: nu(13, FontWeight.w800, C.brown)),
          ],
          if (store.claimed.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Unlocked', style: nu(14, FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final x in rewards.where((x) => store.claimed.contains(x.id)))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(14)),
                  child: Text('${x.emoji} ${x.title}', style: nu(12, FontWeight.w800, C.chipText)),
                ),
            ]),
          ],
        ], actions: const [
          Btn('Close'),
        ]));
    return;
  }
  openDialog((ctx) => AppDialog(title: '🎁 Your reward', children: [
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: springCurve,
            builder: (_, v, c) => Transform.scale(scale: .4 + .6 * v, child: Transform.rotate(angle: (1 - v) * -.6, child: c)),
            child: Text(r.emoji, style: const TextStyle(fontSize: 64)),
          ),
        ),
        const SizedBox(height: 8),
        Text(r.title, textAlign: TextAlign.center, style: nu(18, FontWeight.w800)),
        const SizedBox(height: 4),
        Text(r.desc, textAlign: TextAlign.center, style: nu(14, FontWeight.w600, C.muted, 1.4)),
      ], actions: [
        const Btn('Later'),
        Btn('Claim', kind: Kind.pri, onTap: () {
          store.claim(r);
          Sfx.play('trophy');
          Buzz.medium();
          final s = MediaQuery.sizeOf(ctx);
          confetti(Offset(s.width / 2, s.height * .42));
          toast('Reward claimed · ${r.title}');
          return true;
        }),
      ]));
}

/// Opens the Add book page.
Future<void> openAddBook({Collection? col, bool sub = false}) {
  dropFocus();
  return navKey.currentState!.push(addBookRoute(col: col, sub: sub));
}
