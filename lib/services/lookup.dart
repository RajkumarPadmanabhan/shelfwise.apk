import 'dart:typed_data';

import 'net.dart';

/// What we could find out about a book from its ISBN.
class BookInfo {
  final String isbn, title, author, desc;
  final Uint8List? cover;
  const BookInfo({required this.isbn, required this.title, this.author = '', this.desc = '', this.cover});
}

/// Turns a scanned barcode into an ISBN-13, or null when it isn't a book barcode.
String? isbnFromBarcode(String raw) {
  final d = raw.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
  if (d.length == 13 && (d.startsWith('978') || d.startsWith('979')) && _valid13(d)) return d;
  if (d.length == 10 && _valid10(d)) return _to13(d);
  return null;
}

bool _valid13(String d) {
  var s = 0;
  for (var i = 0; i < 12; i++) {
    s += int.parse(d[i]) * (i.isEven ? 1 : 3);
  }
  return (10 - s % 10) % 10 == int.parse(d[12]);
}

bool _valid10(String d) {
  var s = 0;
  for (var i = 0; i < 10; i++) {
    final v = d[i] == 'X' ? 10 : int.tryParse(d[i]) ?? -100;
    if (v < 0 || (v == 10 && i != 9)) return false;
    s += v * (10 - i);
  }
  return s % 11 == 0;
}

String _to13(String d10) {
  final core = '978${d10.substring(0, 9)}';
  var s = 0;
  for (var i = 0; i < 12; i++) {
    s += int.parse(core[i]) * (i.isEven ? 1 : 3);
  }
  return '$core${(10 - s % 10) % 10}';
}

String _clean(String s) => s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

String _short(String s) => s.length > 240 ? '${s.substring(0, 237).trimRight()}…' : s;

/// Looks the ISBN up on Open Library, then Google Books. Returns null when neither knows it.
Future<BookInfo?> lookupIsbn(String isbn) async {
  BookInfo? info;
  try {
    info = await _openLibrary(isbn);
  } catch (_) {}
  if (info == null || info.desc.isEmpty || info.cover == null) {
    try {
      final g = await _google(isbn);
      if (g != null) {
        info = info == null
            ? g
            : BookInfo(
                isbn: isbn,
                title: info.title,
                author: info.author.isNotEmpty ? info.author : g.author,
                desc: info.desc.isNotEmpty ? info.desc : g.desc,
                cover: info.cover ?? g.cover,
              );
      }
    } catch (_) {}
  }
  return info;
}

Future<BookInfo?> _openLibrary(String isbn) async {
  final j = await Net.json('https://openlibrary.org/api/books?bibkeys=ISBN:$isbn&format=json&jscmd=data') as Map;
  final d = j['ISBN:$isbn'] as Map?;
  if (d == null) return null;
  final title = [d['title'], d['subtitle']].whereType<String>().where((s) => s.isNotEmpty).take(1).join();
  final authors = ((d['authors'] ?? const []) as List).map((a) => (a as Map)['name']).whereType<String>().join(', ');
  var desc = '';
  try {
    final ed = await Net.json('https://openlibrary.org/isbn/$isbn.json') as Map;
    final works = (ed['works'] as List?)?.cast<Map>();
    final key = works?.first['key'];
    if (key is String) {
      final w = await Net.json('https://openlibrary.org$key.json') as Map;
      final dd = w['description'];
      desc = _clean(dd is Map ? '${dd['value'] ?? ''}' : '${dd ?? ''}');
    }
  } catch (_) {}
  Uint8List? cover;
  final c = d['cover'] as Map?;
  final url = (c?['large'] ?? c?['medium']) as String?;
  if (url != null) {
    try {
      final bytes = await Net.bytes(url.replaceFirst('http://', 'https://'));
      if (bytes.length > 1200) cover = bytes; // Open Library returns a tiny placeholder when there's no cover
    } catch (_) {}
  }
  if (title.isEmpty) return null;
  return BookInfo(isbn: isbn, title: title, author: authors, desc: _short(desc), cover: cover);
}

Future<BookInfo?> _google(String isbn) async {
  final j = await Net.json('https://www.googleapis.com/books/v1/volumes?q=isbn:$isbn') as Map;
  final items = (j['items'] as List?)?.cast<Map>();
  if (items == null || items.isEmpty) return null;
  final v = items.first['volumeInfo'] as Map;
  final title = '${v['title'] ?? ''}';
  if (title.isEmpty) return null;
  final authors = ((v['authors'] ?? const []) as List).join(', ');
  Uint8List? cover;
  final links = v['imageLinks'] as Map?;
  final url = (links?['thumbnail'] ?? links?['smallThumbnail']) as String?;
  if (url != null) {
    try {
      cover = await Net.bytes(url.replaceFirst('http://', 'https://').replaceFirst('zoom=1', 'zoom=2').replaceAll('&edge=curl', ''));
    } catch (_) {}
  }
  return BookInfo(isbn: isbn, title: title, author: authors, desc: _short(_clean('${v['description'] ?? ''}')), cover: cover);
}
