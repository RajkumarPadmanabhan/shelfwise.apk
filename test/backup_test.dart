import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelfwise/data/models.dart';
import 'package:shelfwise/data/store.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('shelfwise_test');
    store.images = Directory('${tmp.path}/images')..createSync();
    store.bookFiles = Directory('${tmp.path}/books')..createSync();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, dynamic> backupWith(String file) => {
        'app': 'shelfwise',
        'format': 1,
        'exportedAt': '2026-10-20T10:00:00.000',
        'files': <String, String>{},
        'data': {
          'onboarded': true,
          'profile': {'name': 'Test'},
          'cols': [
            Collection(name: 'Shelf', items: [Item(title: 'A Book', author: 'Someone', file: file, pages: 3, page: 1)]).toJson(),
          ],
          'todos': [Todo(text: 'Read more').toJson()],
          'readLog': {'2026-10-20': 120},
        },
      };

  test('zip backup carries book files and restores them', () async {
    final bytes = Uint8List.fromList(List.generate(50000, (i) => i % 251));
    final src = File('${tmp.path}/abc.pdf')..writeAsBytesSync(bytes);
    final zip = await writeBackupZip(jsonEncode(backupWith('abc.pdf')), [src], '${tmp.path}/b.zip');

    final b = store.parseBackupFile(zip.path);
    expect(b.books, 1);
    expect(b.todos, 1);
    expect(b.copies.keys, ['abc.pdf']);

    await store.restore(b);
    final restored = store.bookFile('abc.pdf');
    expect(restored.existsSync(), isTrue);
    expect(restored.readAsBytesSync(), bytes);
    expect(store.allBooks.single.title, 'A Book');
    expect(store.allBooks.single.page, 1);
    expect(store.readLog['2026-10-20'], 120);
  });

  test('plain JSON backups still import', () {
    final f = File('${tmp.path}/b.json')..writeAsStringSync(jsonEncode(backupWith('x.pdf')));
    final b = store.parseBackupFile(f.path);
    expect(b.books, 1);
    expect(b.copies, isEmpty);
  });

  test('other files are rejected with a friendly message', () {
    final f = File('${tmp.path}/x.json')..writeAsStringSync('{"hello": 1}');
    expect(() => store.parseBackupFile(f.path), throwsA(isA<FormatException>()));
    final z = File('${tmp.path}/x.zip')..writeAsBytesSync([0x50, 0x4B, 3, 4, 0, 0]);
    expect(() => store.parseBackupFile(z.path), throwsA(isA<FormatException>()));
  });
}
