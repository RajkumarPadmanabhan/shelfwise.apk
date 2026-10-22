import 'package:flutter_test/flutter_test.dart';
import 'package:shelfwise/reader/epub.dart';

// alice.epub is the public-domain Project Gutenberg edition of Alice's Adventures in Wonderland.
void main() {
  test('reads EPUB metadata and cover', () async {
    final b = await readEpubMeta('test/fixtures/alice.epub');
    expect(b.title, contains('Alice'));
    expect(b.author, 'Lewis Carroll');
    expect(b.cover, isNotNull);
    expect(b.blocks, isEmpty);
  });

  test('parses chapters into clean paragraphs', () async {
    final b = await readEpub('test/fixtures/alice.epub');
    final text = b.blocks.where((x) => x.kind == 0).map((x) => x.runs.map((r) => r.t).join()).join('\n');
    expect(b.blocks.where((x) => x.kind == 1).length, greaterThan(10)); // headings
    expect(text, contains('Down the Rabbit-Hole'));
    expect(text, contains('Alice was beginning to get very tired of sitting by her sister'));
    expect(text.contains('  '), isFalse); // no doubled spaces from source formatting
  });
}
