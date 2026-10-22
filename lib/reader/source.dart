import 'dart:ui' as ui;

import 'package:pdfx/pdfx.dart';

/// Where the reader's pages come from: a PDF, or an EPUB typeset into pages.
abstract class PageSource {
  int get count;

  /// EPUBs re-flow when the page size or text size changes; PDFs don't.
  bool get reflows;

  /// Page width / height.
  double aspectOf(int i);
  Future<void> open();
  Future<ui.Image?> render(int i, double widthPx);
  Future<void> close();
}

class PdfSource implements PageSource {
  final String path;
  PdfDocument? _doc;
  final _aspect = <int, double>{};
  PdfSource(this.path);

  @override
  int get count => _doc?.pagesCount ?? 0;

  @override
  bool get reflows => false;

  @override
  Future<void> open() async {
    _doc = await PdfDocument.openFile(path);
  }

  /// Size of the first page (or [i]), used before any page has rendered.
  Future<double> measure(int i) async {
    final p = await _doc!.getPage(i + 1);
    final a = p.width / p.height;
    await p.close();
    return _aspect[i] = a;
  }

  @override
  double aspectOf(int i) => _aspect[i] ?? _aspect.values.firstOrNull ?? 1 / 1.414;

  @override
  Future<ui.Image?> render(int i, double widthPx) async {
    final d = _doc;
    if (d == null) return null;
    final p = await d.getPage(i + 1);
    _aspect[i] = p.width / p.height;
    final img = await p.render(width: widthPx, height: widthPx * p.height / p.width, format: PdfPageImageFormat.jpeg, backgroundColor: '#FFFFFF', quality: 92);
    await p.close();
    if (img == null) return null;
    return (await (await ui.instantiateImageCodec(img.bytes)).getNextFrame()).image;
  }

  @override
  Future<void> close() async => _doc?.close();
}
