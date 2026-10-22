import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'posts_models.dart';
import 'sample_data.dart';
import '../services/cd_player.dart';

const shelfMax = 10;

class Reward {
  final String id, emoji, title, desc;
  final int goal;
  final int Function(AppStore s) value;
  const Reward(this.id, this.emoji, this.title, this.desc, this.goal, this.value);
}

int _finished(AppStore s) => s.finishedCount;
int _added(AppStore s) => s.totalBooks;
int _todos(AppStore s) => s.todosDone;
int _decor(AppStore s) => s.cols.fold(0, (a, c) => a + c.items.where((i) => i.isDecor).length);

const rewards = <Reward>[
  Reward('f1', '🌱', 'First chapter', 'You finished your first book.', 1, _finished),
  Reward('t1', '✅', 'Getting things done', 'You completed your first to-do.', 1, _todos),
  Reward('d5', '🪴', 'Interior designer', 'Five decorations brighten your shelves.', 5, _decor),
  Reward('f5', '📗', 'Bookworm', 'Five books finished. Keep turning pages!', 5, _finished),
  Reward('a10', '📚', 'Collector', 'Ten books are sitting on your shelves.', 10, _added),
  Reward('t10', '⚡', 'On a roll', 'Ten to-dos ticked off.', 10, _todos),
  Reward('f10', '🦉', 'Wise owl', 'Ten books finished. The owl approves.', 10, _finished),
  Reward('f25', '🏅', 'Shelf hero', 'Twenty-five books finished.', 25, _finished),
  Reward('a50', '🗄️', 'Library builder', 'Fifty books on your shelves.', 50, _added),
  Reward('t50', '🚀', 'Unstoppable', 'Fifty to-dos done.', 50, _todos),
  Reward('f50', '🏆', 'Library legend', 'Fifty books finished. Legendary.', 50, _finished),
  Reward('f100', '👑', 'Century reader', 'One hundred books finished!', 100, _finished),
];

/// A parsed backup file, ready to restore.
class BackupFile {
  final Map<String, dynamic> data;
  final Map<String, String> files;
  final DateTime? exportedAt;
  final int books, todos, shelves;

  /// Book copies (PDF/EPUB) carried by a zip backup, by file name.
  final Map<String, ArchiveFile> copies;
  final InputFileStream? _stream;
  BackupFile(this.data, this.files, this.exportedAt, this.books, this.todos, this.shelves, {this.copies = const {}, InputFileStream? stream})
      : _stream = stream; // ignore: prefer_initializing_formals

  Future<void> close() async => _stream?.close();
}

/// Everything the app knows, kept in one JSON file on the phone.
class AppStore extends ChangeNotifier {
  AppStore._();
  static final AppStore I = AppStore._();

  late Directory _dir;
  late Directory images;
  late Directory bookFiles;
  late Directory audioFiles;

  bool onboarded = false;
  bool toured = false;
  bool isSample = false;
  List<String> pairedFriends = [];
  String _pairingCode = '';
  String get pairingCode {
    if (_pairingCode.isEmpty) {
      _pairingCode = '${1000 + Random().nextInt(9000)}';
    }
    return _pairingCode;
  }
  Profile profile = Profile();
  List<Collection> cols = [];
  List<String> headings = [];
  List<Todo> todos = [];
  List<StickyNote> todoNotes = [];
  Settings settings = Settings();
  Set<String> claimed = {};
  int? lastBackup;
  Map<String, int> readLog = {}; // 'yyyy-mm-dd' → seconds spent reading
  int goal = 0; // books to finish this year (0 = no goal)
  int goalYear = 0;
  int lastUpdateCheck = 0;
  List<Post> posts = [];
  Set<String> likedPosts = {};
  Set<String> savedPosts = {};
  Map<String, int> sharedPostCounts = {};
  String postsView = 'list';

  Timer? _saveTimer;

  File get _file => File('${_dir.path}/shelfwise.json');

  Future<void> load() async {
    _dir = await getApplicationDocumentsDirectory();
    images = Directory('${_dir.path}/images');
    if (!images.existsSync()) images.createSync(recursive: true);
    bookFiles = Directory('${_dir.path}/books');
    if (!bookFiles.existsSync()) bookFiles.createSync(recursive: true);
    audioFiles = Directory('${_dir.path}/audio');
    if (!audioFiles.existsSync()) audioFiles.createSync(recursive: true);
    try {
      if (_file.existsSync()) {
        fromJson(jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
        _cleanImages();
      }
    } catch (e) {
      debugPrint('Shelfwise: could not read saved data: $e');
    }
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'onboarded': onboarded,
        'toured': toured,
        'isSample': isSample,
        'pairedFriends': pairedFriends,
        'pairingCode': pairingCode,
        'profile': profile.toJson(),
        'cols': cols.map((c) => c.toJson()).toList(),
        'headings': headings,
        'todos': todos.map((t) => t.toJson()).toList(),
        if (todoNotes.isNotEmpty)
          'todoNotes': todoNotes.map((n) => n.toJson()).toList(),
        'settings': settings.toJson(),
        'claimed': claimed.toList(),
        if (lastBackup != null) 'lastBackup': lastBackup,
        if (readLog.isNotEmpty) 'readLog': readLog,
        if (goal > 0) 'goal': goal,
        if (goal > 0) 'goalYear': goalYear,
        if (lastUpdateCheck > 0) 'lastUpdateCheck': lastUpdateCheck,
        'posts': posts.map((p) => p.toJson()).toList(),
        if (likedPosts.isNotEmpty) 'likedPosts': likedPosts.toList(),
        if (savedPosts.isNotEmpty) 'savedPosts': savedPosts.toList(),
        if (sharedPostCounts.isNotEmpty) 'sharedPostCounts': sharedPostCounts,
        'postsView': postsView,
      };

  void fromJson(Map<String, dynamic> j) {
    onboarded = j['onboarded'] == true;
    toured = j['toured'] == true;
    isSample = j['isSample'] == true;
    pairedFriends = ((j['pairedFriends'] ?? const []) as List).cast<String>().toList();
    _pairingCode = (j['pairingCode'] ?? '') as String;
    profile = Profile.fromJson(((j['profile'] ?? const {}) as Map).cast<String, dynamic>());
    cols = ((j['cols'] ?? const []) as List).map((e) => Collection.fromJson((e as Map).cast<String, dynamic>())).toList();
    headings = ((j['headings'] ?? const []) as List).cast<String>().toList();
    todos = ((j['todos'] ?? const []) as List).map((e) => Todo.fromJson((e as Map).cast<String, dynamic>())).toList();
    todoNotes = ((j['todoNotes'] ?? const []) as List).map((e) => StickyNote.fromJson((e as Map).cast<String, dynamic>())).toList();
    settings = Settings.fromJson(((j['settings'] ?? const {}) as Map).cast<String, dynamic>());
    claimed = ((j['claimed'] ?? const []) as List).cast<String>().toSet();
    lastBackup = (j['lastBackup'] as num?)?.toInt();
    readLog = ((j['readLog'] ?? const {}) as Map).map((k, v) => MapEntry('$k', (v as num).toInt()));
    goal = (j['goal'] as num?)?.toInt() ?? 0;
    goalYear = (j['goalYear'] as num?)?.toInt() ?? 0;
    lastUpdateCheck = (j['lastUpdateCheck'] as num?)?.toInt() ?? 0;
    final pList = (j['posts'] as List?)
        ?.map((e) => Post.fromJson((e as Map).cast<String, dynamic>()))
        .where((p) => p.mine)
        .toList();
    posts = pList ?? [];
    likedPosts = ((j['likedPosts'] ?? const []) as List).cast<String>().toSet();
    savedPosts = ((j['savedPosts'] ?? const []) as List).cast<String>().toSet();
    sharedPostCounts = ((j['sharedPostCounts'] ?? const {}) as Map).map((k, v) => MapEntry('$k', (v as num).toInt()));
    postsView = (j['postsView'] ?? 'list') as String;
  }

  /// Call after any mutation: refreshes listeners and writes to disk shortly after.
  void changed() {
    for (final c in cols) {
      _normalize(c);
    }
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(toJson()), flush: true);
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('Shelfwise: save failed: $e');
    }
  }

  // ---------- images ----------

  File imageFile(String name) => File('${images.path}/$name');

  Future<String> saveImage(Uint8List bytes, {String ext = 'jpg'}) async {
    final name = '${newId()}.$ext';
    await imageFile(name).writeAsBytes(bytes, flush: true);
    return name;
  }

  Set<String> _referencedImages() => {
        if (profile.photo != null) profile.photo!,
        for (final c in cols)
          for (final i in c.items)
            if (i.cover != null) i.cover!,
        for (final p in posts)
          if (p.bookCover != null) p.bookCover!,
      };

  File bookFile(String name) => File('${bookFiles.path}/$name');
  File audioFile(String name) => File('${audioFiles.path}/$name');

  /// True when the book's PDF is actually on this phone (backups don't carry PDFs).
  bool copyExists(Item b) => b.file != null && bookFile(b.file!).existsSync();

  void _cleanImages() {
    final keepBooks = {for (final b in allBooks) if (b.file != null) b.file!};
    for (final f in bookFiles.listSync().whereType<File>()) {
      if (!keepBooks.contains(f.uri.pathSegments.last)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    final keep = _referencedImages();
    for (final f in images.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!keep.contains(name)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    final keepAudio = {
      for (final c in cols) ...[
        if (c.mainCd?.audioFile != null) c.mainCd!.audioFile!,
        if (c.subCd?.audioFile != null) c.subCd!.audioFile!,
      ]
    };
    if (audioFiles.existsSync()) {
      for (final f in audioFiles.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (!keepAudio.contains(name)) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    }
  }

  // ---------- posts ----------
  bool isPostLiked(String id) => likedPosts.contains(id);
  bool isPostSaved(String id) => savedPosts.contains(id);
  int postLikes(Post p) => p.likeCount + (isPostLiked(p.id) ? 1 : 0);
  int postShares(Post p) => p.shareCount + (sharedPostCounts[p.id] ?? 0);

  bool toggleLikePost(String id) {
    final liked = likedPosts.contains(id);
    if (liked) {
      likedPosts.remove(id);
    } else {
      likedPosts.add(id);
    }
    changed();
    return !liked;
  }

  bool toggleSavePost(String id) {
    final saved = savedPosts.contains(id);
    if (saved) {
      savedPosts.remove(id);
    } else {
      savedPosts.add(id);
    }
    changed();
    return !saved;
  }

  void incrementSharePost(String id) {
    sharedPostCounts[id] = (sharedPostCounts[id] ?? 0) + 1;
    changed();
  }

  void deletePost(String id) {
    posts.removeWhere((p) => p.id == id);
    likedPosts.remove(id);
    savedPosts.remove(id);
    sharedPostCounts.remove(id);
    changed();
  }

  Post addPost({
    required String bookTitle,
    required String bookAuthor,
    String? bookCover,
    required List<PostItem> items,
  }) {
    final myName = profile.name.trim().isNotEmpty ? profile.name.trim() : 'Alex Reader';
    final myHandle = profile.handle.trim().isNotEmpty ? profile.handle.trim() : 'alexreads';
    final newPost = Post(
      id: 'm_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}',
      mine: true,
      authorName: myName,
      authorHandle: myHandle,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      bookCover: bookCover,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      likeCount: 0,
      shareCount: 0,
      items: items,
    );
    posts.insert(0, newPost);
    changed();
    return newPost;
  }

  void setPostsView(String view) {
    if (postsView != view) {
      postsView = view;
      changed();
    }
  }

  // ---------- library ----------

  Iterable<Item> get allBooks => cols.expand((c) => c.books);
  int get totalBooks => allBooks.length;
  int get finishedCount => allBooks.where((b) => b.finished).length;
  int get readingCount => allBooks.where((b) => !b.finished).length;

  int rowCount(Collection c, bool sub) => c.items.where((i) => i.sub == sub).length;
  int bookCount(Collection c, bool sub) => c.items.where((i) => !i.isDecor && i.sub == sub).length;

  /// Drops decorations (last first) until the row has a free spot. Returns how many went.
  int makeRoom(Collection c, bool sub) {
    var gone = 0;
    while (rowCount(c, sub) >= shelfMax) {
      final ix = c.items.lastIndexWhere((i) => i.isDecor && i.sub == sub);
      if (ix < 0) break;
      c.items.removeAt(ix);
      gone++;
    }
    return gone;
  }

  void _normalize(Collection c) {
    final subAll = c.items.where((i) => i.sub).length;
    final mainN = bookCount(c, false);
    if (subAll > 0 && !c.subOn) c.subOn = true;
    if (c.subOn && subAll == 0 && mainN < shelfMax) {
      c.subOn = false;
      c.subOpen = false;
    }
  }

  /// Where a new book would land on [c]: false = main shelf, true = sub shelf, null = full.
  bool? placeFor(Collection c) {
    if (bookCount(c, false) < shelfMax) return false;
    if (bookCount(c, true) < shelfMax) return true;
    return null;
  }

  /// Adds [b] to [c] on the given row. Returns decorations removed to make room.
  int addBook(Collection c, Item b, {required bool sub}) {
    b.sub = sub;
    if (sub) {
      c.subOn = true;
      c.subOpen = true;
    }
    final gone = makeRoom(c, sub);
    if (b.finished) b.finishedAt ??= DateTime.now().millisecondsSinceEpoch;
    c.items.add(b);
    changed();
    return gone;
  }

  bool addDecor(Collection c, String key, {required bool sub}) {
    if (rowCount(c, sub) >= shelfMax) return false;
    c.items.add(Item.decor(key, sub: sub));
    changed();
    return true;
  }

  void setLights(Collection c, String? kind, {required bool sub, bool all = false}) {
    if (all) {
      for (final col in cols) {
        col.setLights(kind, sub: false);
        col.setLights(kind, sub: true);
      }
    } else {
      c.setLights(kind, sub: sub);
    }
    changed();
  }

  bool addSticker(Collection c, String kind, {required bool sub}) {
    if (c.stickersFor(sub: sub).length >= 12) return false;
    final rnd = Random();
    final x = 18.0 + rnd.nextDouble() * 60.0;
    final y = 65.0 + rnd.nextDouble() * 18.0;
    final r = (rnd.nextDouble() * 30.0 - 15.0);
    c.stickers.add(ShelfSticker(kind: kind, x: x, y: y, r: r, sub: sub));
    changed();
    return true;
  }

  void removeSticker(Collection c, String stickerId) {
    c.stickers.removeWhere((s) => s.id == stickerId);
    changed();
  }

  void moveSticker(Collection c, String stickerId, double x, double y) {
    for (final s in c.stickers) {
      if (s.id == stickerId) {
        s.x = x.clamp(2.0, 96.0);
        s.y = y.clamp(2.0, 90.0);
        changed();
        break;
      }
    }
  }

  bool addStickyNote(Collection c, {
    required String text,
    required String color,
    required String ink,
    required bool sub,
    String size = 'm',
  }) {
    if (c.notesFor(sub: sub).length >= 10) return false;
    final rnd = Random();
    final x = 12.0 + rnd.nextDouble() * 66.0;
    final y = 40.0 + rnd.nextDouble() * 22.0;
    final r = (rnd.nextDouble() * 8.0 - 4.0);
    c.stickyNotes.add(StickyNote(
      text: text,
      color: color,
      ink: ink,
      size: size,
      x: x,
      y: y,
      r: r,
      sub: sub,
      shelfId: c.id,
    ));
    changed();
    return true;
  }

  void updateStickyNote(Collection c, String id, {String? text, String? color, String? ink, String? size}) {
    for (final n in c.stickyNotes) {
      if (n.id == id) {
        if (text != null) n.text = text;
        if (color != null) n.color = color;
        if (ink != null) n.ink = ink;
        if (size != null) n.size = size;
        changed();
        break;
      }
    }
  }

  void removeStickyNote(Collection c, String noteId) {
    c.stickyNotes.removeWhere((n) => n.id == noteId);
    changed();
  }

  void moveStickyNote(Collection c, String noteId, double x, double y) {
    for (final n in c.stickyNotes) {
      if (n.id == noteId) {
        n.x = x.clamp(2.0, 96.0);
        n.y = y.clamp(2.0, 90.0);
        changed();
        break;
      }
    }
  }

  bool addCd(Collection c, {bool sub = false}) {
    if (c.cdFor(sub: sub) != null) return false;
    c.setCd(ShelfCd(sub: sub, x: 74.0, y: 12.0), sub: sub);
    changed();
    return true;
  }

  void moveCd(Collection c, double x, double y, {bool sub = false}) {
    final cd = c.cdFor(sub: sub);
    if (cd != null) {
      cd.x = x.clamp(2.0, 96.0);
      cd.y = y.clamp(2.0, 90.0);
      changed();
    }
  }

  void setCdSong(Collection c, {required String fileName, required String title, bool sub = false}) {
    final cd = c.cdFor(sub: sub);
    if (cd != null) {
      if (cd.audioFile != null && cd.audioFile != fileName) {
        deleteAudio(cd.audioFile);
      }
      cd.audioFile = fileName;
      cd.title = title;
      changed();
    }
  }

  void removeCd(Collection c, {bool sub = false}) {
    final cd = c.cdFor(sub: sub);
    if (cd != null) {
      ShelfCdPlayer.I.stopIfPlaying(cd.id);
      if (cd.audioFile != null) {
        deleteAudio(cd.audioFile);
      }
      c.setCd(null, sub: sub);
      changed();
    }
  }

  void deleteAudio(String? name) {
    if (name == null || name.isEmpty) return;
    try {
      final f = audioFile(name);
      if (f.existsSync()) {
        f.deleteSync();
      }
    } catch (e) {
      debugPrint('Shelfwise: could not delete audio file $name: $e');
    }
  }

  void addTodoStickyNote({
    required String text,
    required String color,
    required String ink,
    String size = 'm',
    double? x,
    double? y,
  }) {
    final rnd = Random();
    final r = (rnd.nextDouble() * 6.0 - 3.0);
    todoNotes.add(StickyNote(
      text: text,
      color: color,
      ink: ink,
      size: size,
      r: r,
      isTodo: true,
      x: x ?? (15.0 + rnd.nextDouble() * 30.0),
      y: y ?? (25.0 + rnd.nextDouble() * 20.0),
    ));
    changed();
  }

  void moveTodoStickyNote(String id, double x, double y) {
    for (final n in todoNotes) {
      if (n.id == id) {
        n.x = x.clamp(1.0, 99.0);
        n.y = y.clamp(1.0, 99.0);
        changed();
        break;
      }
    }
  }

  void updateTodoStickyNote(String id, {String? text, String? color, String? ink, String? size}) {
    for (final n in todoNotes) {
      if (n.id == id) {
        if (text != null) n.text = text;
        if (color != null) n.color = color;
        if (ink != null) n.ink = ink;
        if (size != null) n.size = size;
        changed();
        break;
      }
    }
  }

  void removeTodoStickyNote(String id) {
    todoNotes.removeWhere((n) => n.id == id);
    changed();
  }

  /// Pin [noteId] to [todoId] with the note's top-left at [offX],[offY]
  /// relative to the todo tile's top-left corner.
  void pinTodoStickyNote(String noteId, String todoId, double offX, double offY) {
    for (final n in todoNotes) {
      if (n.id == noteId) {
        n.pinnedTodoId = todoId;
        n.pinOffsetX = offX;
        n.pinOffsetY = offY;
        changed();
        break;
      }
    }
  }

  /// Remove the pin so the note floats freely again (keeps its current x/y).
  void unpinTodoStickyNote(String noteId) {
    for (final n in todoNotes) {
      if (n.id == noteId) {
        n.pinnedTodoId = null;
        n.pinOffsetX = null;
        n.pinOffsetY = null;
        changed();
        break;
      }
    }
  }

  Collection? colOf(Item it) {
    for (final c in cols) {
      if (c.items.contains(it)) return c;
    }
    return null;
  }

  /// Removes [it]; returns enough to undo it.
  (Collection, int, Item)? removeItem(Item it) {
    final c = colOf(it);
    if (c == null) return null;
    final ix = c.items.indexOf(it);
    c.items.removeAt(ix);
    changed();
    return (c, ix, it);
  }

  void restoreItem((Collection, int, Item) r) {
    final (c, ix, it) = r;
    if (!cols.contains(c)) cols.add(c);
    c.items.insert(ix.clamp(0, c.items.length), it);
    changed();
  }

  void setStatus(Item b, String s) {
    b.status = s;
    b.finishedAt = s == 'f' ? (b.finishedAt ?? DateTime.now().millisecondsSinceEpoch) : null;
    if (s == 'f') {
      // Only reading books have bookmarks, finished books do not keep reading bookmarks
      b.marks.removeWhere((m) => m.note.isEmpty);
    }
    changed();
  }

  /// Moves [b] to collection [to]; returns false when that collection is full.
  bool moveBook(Item b, Collection to) {
    final place = placeFor(to);
    if (place == null) return false;
    colOf(b)?.items.remove(b);
    b.sub = place;
    if (place) {
      to.subOn = true;
      to.subOpen = true;
    }
    makeRoom(to, place);
    to.items.add(b);
    changed();
    return true;
  }

  void reorder(Collection c, Item from, Item target, {required bool before}) {
    final a = c.items;
    final fi = a.indexOf(from);
    var ti = a.indexOf(target);
    if (fi < 0 || ti < 0 || fi == ti) return;
    a.removeAt(fi);
    ti = a.indexOf(target);
    a.insert(before ? ti : ti + 1, from);
    changed();
  }

  bool hasBook(String title, String author) =>
      allBooks.any((b) => b.title.toLowerCase() == title.toLowerCase() && b.author.toLowerCase() == author.toLowerCase());

  // ---------- to-dos ----------

  int get todosDone => todos.where((t) => t.done).length;

  static DateTime endOfToday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, 23, 59, 59);
  }

  /// Open to-dos due today or earlier.
  List<Todo> get dueTodos => todos.where((t) => !t.done && t.due != null && t.due! <= endOfToday().millisecondsSinceEpoch).toList()
    ..sort((a, b) => a.due!.compareTo(b.due!));

  bool isOverdue(Todo t) => !t.done && t.due != null && t.due! < DateTime.now().millisecondsSinceEpoch;

  void toggleTodo(Todo t) {
    t.done = !t.done;
    t.doneAt = t.done ? DateTime.now().millisecondsSinceEpoch : null;
    changed();
  }

  // ---------- rewards ----------

  List<Reward> get unclaimed => rewards.where((r) => !claimed.contains(r.id) && r.value(this) >= r.goal).toList();

  Reward? get nextReward {
    for (final r in rewards) {
      if (!claimed.contains(r.id) && r.value(this) < r.goal) return r;
    }
    return null;
  }

  void claim(Reward r) {
    claimed.add(r.id);
    changed();
  }

  int get bellCount => dueTodos.length + unclaimed.length;

  // ---------- stats ----------

  /// Finished books per month for the last [n] months (oldest first).
  List<(String, int)> finishedByMonth([int n = 6]) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    return List.generate(n, (i) {
      final m = DateTime(now.year, now.month - (n - 1 - i));
      final next = DateTime(m.year, m.month + 1);
      final count = allBooks.where((b) {
        if (b.finishedAt == null) return false;
        final d = DateTime.fromMillisecondsSinceEpoch(b.finishedAt!);
        return !d.isBefore(m) && d.isBefore(next);
      }).length;
      return (names[m.month - 1], count);
    });
  }

  /// Things you did per day (books added or finished, to-dos completed) over [days].
  List<int> activity(int days) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    final out = List<int>.filled(days, 0);
    void add(int? ms) {
      if (ms == null) return;
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      final ix = DateTime(d.year, d.month, d.day).difference(start).inDays;
      if (ix >= 0 && ix < days) out[ix]++;
    }

    for (final b in allBooks) {
      add(b.addedAt);
      add(b.finishedAt);
    }
    for (final t in todos) {
      add(t.doneAt);
    }
    return out;
  }

  // ---------- reading time & goal ----------

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Records [seconds] of reading in [b]'s copy. Saved with the next [changed].
  void addReading(Item b, int seconds) {
    if (seconds <= 0) return;
    b.readMs += seconds * 1000;
    final k = dayKey(DateTime.now());
    readLog[k] = (readLog[k] ?? 0) + seconds;
  }

  int readSecondsIn(String p) {
    final from = dayKey(periodStart(p));
    return readLog.entries.where((e) => e.key.compareTo(from) >= 0).fold(0, (a, e) => a + e.value);
  }

  /// Minutes read on each of the last [days] days (oldest first).
  List<int> readMinutes(int days) {
    final n = DateTime.now();
    return List.generate(days, (i) => ((readLog[dayKey(DateTime(n.year, n.month, n.day - (days - 1 - i)))] ?? 0) / 60).round());
  }

  int get goalThisYear => goalYear == DateTime.now().year ? goal : 0;
  int get finishedThisYear => finishedIn('year').length;

  void setGoal(int n) {
    goal = n;
    goalYear = DateTime.now().year;
    changed();
  }

  /// The best-rated finished book in the period (4 stars or more).
  Item? topRated(String p) {
    final l = finishedIn(p).where((b) => b.rating >= 4).toList()..sort((a, b) => b.rating.compareTo(a.rating));
    return l.isEmpty ? null : l.first;
  }

  // ---------- periods (stats filter + Rewind) ----------

  static DateTime periodStart(String p) {
    final n = DateTime.now();
    return switch (p) {
      'month' => DateTime(n.year, n.month),
      'year' => DateTime(n.year),
      _ => DateTime(1970),
    };
  }

  static String periodLabel(String p) {
    const mon = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final n = DateTime.now();
    return switch (p) {
      'month' => '${mon[n.month - 1]} ${n.year}',
      'year' => '${n.year} so far',
      _ => 'All time',
    };
  }

  bool _in(int? ms, String p) => ms != null && ms >= periodStart(p).millisecondsSinceEpoch;

  List<Item> finishedIn(String p) => allBooks.where((b) => _in(b.finishedAt, p)).toList()..sort((a, b) => b.finishedAt!.compareTo(a.finishedAt!));
  List<Item> addedIn(String p) => allBooks.where((b) => _in(b.addedAt, p)).toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  int todosDoneIn(String p) => todos.where((t) => t.done && _in(t.doneAt, p)).length;
  int pagesIn(String p) => allBooks.where((b) => b.file != null && _in(b.readAt, p)).fold(0, (a, b) => a + b.page + 1);

  /// Finished books bucketed for the chosen period: weeks of this month, months of this year,
  /// or years (falling back to the last six months when everything is recent).
  List<(String, int)> barsFor(String p) {
    final n = DateTime.now();
    final fin = allBooks.where((b) => b.finishedAt != null).map((b) => DateTime.fromMillisecondsSinceEpoch(b.finishedAt!)).toList();
    if (p == 'month') {
      final weeks = ((DateTime(n.year, n.month + 1, 0).day) / 7).ceil();
      return List.generate(weeks, (w) => ('W${w + 1}', fin.where((d) => d.year == n.year && d.month == n.month && (d.day - 1) ~/ 7 == w).length));
    }
    if (p == 'year') {
      const m = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
      return List.generate(12, (i) => (m[i], fin.where((d) => d.year == n.year && d.month == i + 1).length));
    }
    final first = fin.isEmpty ? n.year : fin.map((d) => d.year).reduce(min);
    if (n.year - first >= 1) {
      return [for (var y = max(first, n.year - 5); y <= n.year; y++) ('$y', fin.where((d) => d.year == y).length)];
    }
    return finishedByMonth();
  }

  /// The shelf with the most finished (or else added) books in the period.
  (Collection, int)? topShelf(String p) {
    (Collection, int)? best;
    for (final c in cols) {
      final f = c.books.where((b) => _in(b.finishedAt, p)).length;
      final score = f > 0 ? f : c.books.where((b) => _in(b.addedAt, p)).length;
      if (score > 0 && (best == null || score > best.$2)) best = (c, score);
    }
    return best;
  }

  /// Longest run of consecutive days with any reading activity in the period.
  int streak(String p) {
    final days = <int>{};
    void add(int? ms) {
      if (!_in(ms, p)) return;
      final d = DateTime.fromMillisecondsSinceEpoch(ms!);
      days.add(DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000);
    }

    for (final b in allBooks) {
      add(b.addedAt);
      add(b.finishedAt);
      add(b.readAt);
    }
    for (final t in todos) {
      add(t.doneAt);
    }
    final from = dayKey(periodStart(p));
    for (final e in readLog.entries) {
      if (e.key.compareTo(from) < 0 || e.value < 60) continue;
      final parts = e.key.split('-').map(int.parse).toList();
      days.add(DateTime.utc(parts[0], parts[1], parts[2]).millisecondsSinceEpoch ~/ 86400000);
    }
    var best = 0;
    for (final d in days) {
      if (days.contains(d - 1)) continue;
      var len = 1;
      while (days.contains(d + len)) {
        len++;
      }
      best = max(best, len);
    }
    return best;
  }

  // ---------- setup ----------

  void setupFresh({String name = '', required bool sample, String email = ''}) {
    isSample = sample;
    final finalName = name.trim().isNotEmpty ? name.trim() : (email.trim().isNotEmpty ? nameFromEmail(email) : 'Reader');
    profile = Profile(name: finalName, handle: handleFor(finalName), email: email.trim(), bio: 'Reading one page at a time.');
    headings = [];
    claimed = {};
    if (sample) {
      _seedSample();
    } else {
      cols = [
        Collection(name: 'Reading now', emoji: '📖', items: [Item.decor('lamp')]),
        Collection(name: 'Want to read', emoji: '🔖', items: [Item.decor('pot')]),
        Collection(name: 'Favourites', emoji: '⭐', items: [Item.decor('candle')]),
      ];
      // Actual library starts clean with no dummy to-dos
      todos = [];
      todoNotes = [];
    }
    onboarded = true;
    toured = false;
    changed();
  }

  void logout() {
    onboarded = false;
    toured = false;
    changed();
  }

  Future<void> deleteUser() async {
    profile = Profile();
    cols = [
      Collection(name: 'Reading now', emoji: '📖'),
      Collection(name: 'Want to read', emoji: '🔖'),
      Collection(name: 'Favourites', emoji: '⭐'),
    ];
    todos = [];
    todoNotes = [];
    headings = [];
    claimed = {};
    settings = Settings();
    isSample = false;
    pairedFriends = [];
    _pairingCode = '';
    readLog = {};
    goal = 0;
    goalYear = 0;
    onboarded = false;
    toured = false;

    try {
      if (images.existsSync()) {
        for (final f in images.listSync()) {
          try {
            f.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
      if (bookFiles.existsSync()) {
        for (final f in bookFiles.listSync()) {
          try {
            f.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
      if (audioFiles.existsSync()) {
        for (final f in audioFiles.listSync()) {
          try {
            f.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
      ShelfCdPlayer.I.stop();
      if (_file.existsSync()) {
        _file.deleteSync();
      }
    } catch (e) {
      debugPrint('deleteUser cleanup error: $e');
    }
    changed();
  }

  Item receiveSharedBook(Item book, {required String fromUser, bool permanent = false}) {
    Collection? sharedCol;
    for (final c in cols) {
      if (c.name.trim().toLowerCase() == 'shared books') {
        sharedCol = c;
        break;
      }
    }
    if (sharedCol == null) {
      sharedCol = Collection(name: 'Shared books', emoji: '🤝');
      cols.insert(0, sharedCol);
    }
    final copy = book.copy();
    copy.id = newId();
    final cleanSender = fromUser.trim().isNotEmpty ? fromUser.trim() : 'Friend';
    copy.fromUser = cleanSender;
    sharedCol.items.insert(0, copy);

    if (permanent && !pairedFriends.contains(cleanSender)) {
      pairedFriends.add(cleanSender);
    }
    changed();
    return copy;
  }

  static String nameFromEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return 'Reader';
    final userPart = trimmed.split('@').first;
    final cleaned = userPart.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), ' ').trim();
    if (cleaned.isEmpty) return 'Reader';
    final words = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final titleCased = words.map((w) => '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1).toLowerCase() : ''}').join(' ');
    return titleCased.isEmpty ? 'Reader' : titleCased;
  }

  static String handleFor(String name) {
    final h = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return h.isEmpty ? 'reader' : '${h}reads';
  }

  void _seedSample() {
    final now = DateTime.now();
    final day = const Duration(days: 1).inMilliseconds;
    var g = 0;
    const decor = <String, List<String>>{
      'Kindle': ['cup', 'pens'],
      'Beach reads': ['duck', 'succ'],
      'Fantasy': ['owl', 'lamp'],
      'Classics': ['clock'],
      'Non-fiction': ['globe', 'hour'],
      'Book club': ['teddy', 'candle'],
    };
    cols = sampleShelves.map((s) {
      final (name, emoji, books) = s;
      final items = <Item>[];
      for (final raw in books) {
        g++;
        final p = raw.split('~');
        final reading = g % 9 == 1;
        items.add(Item(
          title: p[0],
          author: p[1],
          desc: sampleDescriptions[p[0]] ?? '',
          status: reading ? 'r' : 'f',
          addedAt: now.millisecondsSinceEpoch - ((g * 7) % 40) * day,
          finishedAt: reading ? null : now.millisecondsSinceEpoch - ((g * 37) % 175) * day,
          tags: g % 11 == 3 ? ['Favourites'] : null,
        ));
      }
      for (final k in decor[name] ?? const <String>[]) {
        items.insert((items.length * 0.6).round(), Item.decor(k));
      }
      return Collection(name: name, emoji: emoji, items: items);
    }).toList();
    // the mockup seeds a sub shelf so Home has one to show
    final mystery = cols[3];
    for (final raw in ['Dracula~Bram Stoker', 'The Woman in White~Wilkie Collins', 'And Then There Were None~Agatha Christie']) {
      final p = raw.split('~');
      mystery.items.add(Item(title: p[0], author: p[1], status: 'f', sub: true, finishedAt: now.millisecondsSinceEpoch - 20 * day));
    }
    mystery.subOn = true;
    headings = ['Favourites'];
    todos = [
      Todo(text: 'Finish the last 80 pages of The Name of the Wind before Sunday', book: 'The Name of the Wind', tags: ['fantasy', 'weekend'], due: DateTime(now.year, now.month, now.day, 20).millisecondsSinceEpoch, starred: true),
      Todo(text: 'Return Rebecca to the library', book: 'Rebecca', tags: ['errand'], due: DateTime(now.year, now.month, now.day + 2, 18).millisecondsSinceEpoch),
      Todo(text: 'Pick next month’s book club read', tags: ['bookclub']),
      Todo(text: 'Write three lines about Piranesi while it’s fresh', book: 'Piranesi', tags: ['notes']),
      Todo(text: 'Read 20 minutes before bed', tags: ['habit']),
      Todo(text: 'Order a copy of Project Hail Mary', done: true, doneAt: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch),
      Todo(text: 'Reorganise the Classics shelf', done: true, doneAt: now.subtract(const Duration(days: 3)).millisecondsSinceEpoch),
    ];
    // a sample library would unlock almost every reward at once; leave one to discover
    final earned = rewards.where((r) => r.value(this) >= r.goal).toList();
    claimed = earned.take(earned.length - 1).map((r) => r.id).toSet();
  }

  // ---------- backup ----------

  Iterable<File> get _copies =>
      {for (final b in allBooks) if (b.file != null) b.file!}.map(bookFile).where((f) => f.existsSync());

  /// Total size of the PDF/EPUB copies a full backup would carry.
  int get copiesBytes => _copies.fold(0, (a, f) => a + f.lengthSync());

  /// Writes a backup to a temporary file: plain JSON, or a zip that also carries
  /// the book copies when [withCopies] is set and there are any.
  Future<File> exportBackup({bool withCopies = false}) async {
    final files = <String, String>{};
    for (final name in _referencedImages()) {
      final f = imageFile(name);
      if (f.existsSync()) files[name] = base64Encode(await f.readAsBytes());
    }
    final now = DateTime.now();
    final body = jsonEncode({
      'app': 'shelfwise',
      'format': 1,
      'exportedAt': now.toIso8601String(),
      'data': toJson(),
      'files': files,
    });
    final tmp = await getTemporaryDirectory();
    String two(int n) => n.toString().padLeft(2, '0');
    final base = '${tmp.path}/shelfwise-backup-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}';
    final copies = withCopies ? _copies.toList() : const <File>[];
    late final File out;
    if (copies.isEmpty) {
      out = File('$base.json');
      await out.writeAsString(body, flush: true);
    } else {
      out = await writeBackupZip(body, copies, '$base.zip');
    }
    lastBackup = now.millisecondsSinceEpoch;
    changed();
    return out;
  }

  /// Reads a backup file (JSON or zip). Throws [FormatException] with a friendly message when it isn't one.
  BackupFile parseBackupFile(String path) {
    final f = File(path);
    final head = f.openSync()..setPositionSync(0);
    final magic = head.readSync(2);
    head.closeSync();
    if (magic.length == 2 && magic[0] == 0x50 && magic[1] == 0x4B) {
      final stream = InputFileStream(path);
      try {
        final arc = ZipDecoder().decodeStream(stream);
        final json = arc.findFile('backup.json')?.readBytes();
        if (json == null) throw const FormatException('That file isn’t a Shelfwise backup.');
        final copies = {
          for (final e in arc.files)
            if (e.isFile && e.name.startsWith('books/') && !e.name.contains('..')) e.name.substring(6): e,
        };
        return parseBackup(json, copies: copies, stream: stream);
      } on FormatException {
        stream.close();
        rethrow;
      } catch (_) {
        stream.close();
        throw const FormatException('That file isn’t a Shelfwise backup.');
      }
    }
    return parseBackup(f.readAsBytesSync());
  }

  BackupFile parseBackup(Uint8List bytes, {Map<String, ArchiveFile> copies = const {}, InputFileStream? stream}) {
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const FormatException('That file isn’t a Shelfwise backup.');
    }
    if (j is! Map || j['app'] != 'shelfwise' || j['data'] is! Map) {
      throw const FormatException('That file isn’t a Shelfwise backup.');
    }
    final data = (j['data'] as Map).cast<String, dynamic>();
    final files = ((j['files'] ?? const {}) as Map).cast<String, String>();
    final c = ((data['cols'] ?? const []) as List);
    var books = 0;
    for (final x in c) {
      books += (((x as Map)['items'] ?? const []) as List).where((i) => (i as Map)['g'] == null).length;
    }
    return BackupFile(data, files, DateTime.tryParse('${j['exportedAt']}'), books, ((data['todos'] ?? const []) as List).length, c.length,
        copies: copies, stream: stream);
  }

  Future<void> restore(BackupFile b) async {
    try {
      for (final e in b.files.entries) {
        if (e.key.contains('/') || e.key.contains('..')) continue;
        await imageFile(e.key).writeAsBytes(base64Decode(e.value), flush: true);
      }
      for (final e in b.copies.entries) {
        if (e.key.contains('/')) continue;
        final bytes = e.value.readBytes();
        if (bytes != null) await bookFile(e.key).writeAsBytes(bytes, flush: true);
      }
    } finally {
      await b.close();
    }
    final keepSettings = settings;
    fromJson(b.data);
    settings = keepSettings; // reminders/sounds are a property of this phone
    onboarded = true;
    toured = true;
    changed();
    await flush();
  }
}

AppStore get store => AppStore.I;

/// Writes a zip backup: `backup.json` plus each book copy under `books/` (stored, not compressed).
Future<File> writeBackupZip(String json, List<File> copies, String path) async {
  final jf = File('${File(path).parent.path}/backup.json');
  await jf.writeAsString(json, flush: true);
  final zip = ZipFileEncoder()..create(path);
  await zip.addFile(jf, 'backup.json');
  for (final f in copies) {
    await zip.addFile(f, 'books/${f.uri.pathSegments.last}', 0);
  }
  await zip.close();
  await jf.delete();
  return File(path);
}
