import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../data/store.dart';
import '../version.dart';
import 'net.dart';

class Release {
  final String version, notes, apkUrl;
  final int size;
  const Release(this.version, this.notes, this.apkUrl, this.size);
}

/// Checks GitHub for a newer Shelfwise and installs it (people sideload the APK,
/// so nothing else would tell them an update exists).
class Updater {
  static final available = ValueNotifier<Release?>(null);
  static const _api = 'https://api.github.com/repos/$repo/releases/latest';

  /// 1.10.0 > 1.9.2
  static bool newer(String a, String b) {
    List<int> p(String v) => v.replaceFirst(RegExp('^v'), '').split(RegExp(r'[.+-]')).take(3).map((e) => int.tryParse(e) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d > 0;
    }
    return false;
  }

  /// Quietly checks at most every 20 hours unless [force]d. Returns the newer release, if any.
  static Future<Release?> check({bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - store.lastUpdateCheck < const Duration(hours: 20).inMilliseconds) return available.value;
    try {
      final j = await Net.json(_api) as Map;
      store.lastUpdateCheck = now;
      store.changed();
      final tag = '${j['tag_name'] ?? ''}';
      final assets = ((j['assets'] ?? const []) as List).cast<Map>();
      final apk = assets.where((a) => '${a['name']}'.endsWith('.apk')).firstOrNull;
      if (apk == null || !newer(tag, appVersion)) {
        available.value = null;
        return null;
      }
      final notes = '${j['body'] ?? ''}'.replaceAll('\r', '');
      return available.value = Release(tag.replaceFirst('v', ''), notes, '${apk['browser_download_url']}', (apk['size'] as num?)?.toInt() ?? 0);
    } catch (e) {
      debugPrint('Shelfwise: update check failed: $e');
      if (force) rethrow;
      return null;
    }
  }

  /// Downloads the APK, then opens Android's installer. Returns an error message, or null.
  static Future<String?> install(Release r, void Function(double) onProgress) async {
    try {
      final bytes = await Net.bytes(r.apkUrl, onProgress: (got, total) {
        final t = total > 0 ? total : r.size;
        if (t > 0) onProgress(got / t);
      });
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/shelfwise-${r.version}.apk');
      await f.writeAsBytes(bytes, flush: true);
      final res = await OpenFilex.open(f.path, type: 'application/vnd.android.package-archive');
      return res.type == ResultType.done ? null : res.message;
    } catch (e) {
      return 'The download didn’t finish. Check your connection and try again.';
    }
  }
}
