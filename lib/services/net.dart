import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../version.dart';

/// Tiny HTTP helpers (no extra packages). Throws on network errors.
class Net {
  static final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..userAgent = 'Shelfwise/$appVersion (+$siteUrl)';

  static Future<Uint8List> bytes(String url, {void Function(int got, int total)? onProgress}) async {
    final req = await _client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    final total = res.contentLength;
    final out = BytesBuilder(copy: false);
    await for (final chunk in res) {
      out.add(chunk);
      onProgress?.call(out.length, total);
    }
    return out.takeBytes();
  }

  static Future<dynamic> json(String url) async => jsonDecode(utf8.decode(await bytes(url)));
}
