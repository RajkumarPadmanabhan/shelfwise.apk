import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../reader/epub.dart';
import '../widgets/common.dart';

/// A PDF or EPUB copied into the app, ready to hang on a book.
class PickedCopy {
  final String file;
  final int pages; // 0 for EPUBs until they are first opened (pages depend on the screen)
  final String suggestedTitle, author, desc;
  final Uint8List? cover;
  final int bytes;
  PickedCopy(this.file, this.pages, this.suggestedTitle, this.bytes, {this.author = '', this.desc = '', this.cover});
  bool get isEpub => file.endsWith('.epub');
}

/// Lets the person pick a PDF or EPUB from their phone and copies it into Shelfwise.
/// Returns null when cancelled or when the file can't be read.
Future<PickedCopy?> pickBookCopy() async {
  final PlatformFile? f;
  try {
    f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf', 'epub'], dialogTitle: 'Choose your copy (PDF or EPUB)');
  } catch (_) {
    toast('Couldn’t open the file picker');
    return null;
  }
  if (f == null) return null;
  final lower = f.name.toLowerCase();
  if (!lower.endsWith('.pdf') && !lower.endsWith('.epub')) {
    toast('Pick a PDF or EPUB file');
    return null;
  }
  final epub = lower.endsWith('.epub');
  toast('Copying ${f.name}…');
  final name = '${newId()}.${epub ? 'epub' : 'pdf'}';
  final dest = store.bookFile(name);
  try {
    final src = f.path;
    if (src != null && File(src).existsSync()) {
      await File(src).copy(dest.path);
    } else {
      await dest.writeAsBytes(await f.readAsBytes(), flush: true);
    }
    if (epub) {
      final meta = await readEpubMeta(dest.path);
      return PickedCopy(name, 0, meta.title.isEmpty ? titleFromFile(f.name) : meta.title, dest.lengthSync(),
          author: meta.author, desc: meta.desc, cover: meta.cover);
    }
    final doc = await PdfDocument.openFile(dest.path);
    final pages = doc.pagesCount;
    await doc.close();
    if (pages <= 0) throw const FormatException('empty');
    return PickedCopy(name, pages, titleFromFile(f.name), dest.lengthSync());
  } catch (_) {
    if (dest.existsSync()) dest.deleteSync();
    toast(epub ? 'That EPUB couldn’t be opened' : 'That PDF couldn’t be opened');
    return null;
  }
}

/// "web-hacking-101.pdf" → "Web Hacking 101".
String titleFromFile(String name) {
  final base = name.replaceAll(RegExp(r'\.(pdf|epub)$', caseSensitive: false), '').replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  return base
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : (w == w.toLowerCase() ? w[0].toUpperCase() + w.substring(1) : w))
      .join(' ');
}

String fmtSize(int bytes) =>
    bytes > 1 << 20 ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

/// Attaches a picked copy to an existing book (replacing any older one).
Future<void> attachCopy(Item b, PickedCopy c) async {
  final old = b.file;
  b
    ..file = c.file
    ..pages = c.pages
    ..page = 0
    ..pos = 0
    ..marks = [];
  if (b.cover == null && c.cover != null) b.cover = await store.saveImage(c.cover!);
  if (b.desc.isEmpty && c.desc.isNotEmpty) b.desc = c.desc.length > 240 ? '${c.desc.substring(0, 237)}…' : c.desc;
  store.changed();
  if (old != null && old != c.file) {
    final f = store.bookFile(old);
    if (f.existsSync()) f.deleteSync();
  }
}

void detachCopy(Item b) {
  final old = b.file;
  b
    ..file = null
    ..pages = 0
    ..page = 0
    ..pos = 0
    ..marks = []
    ..readAt = null;
  store.changed();
  if (old != null) {
    final f = store.bookFile(old);
    if (f.existsSync()) f.deleteSync();
  }
}
