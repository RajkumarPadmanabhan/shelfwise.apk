import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/common.dart';
import 'sfx.dart';

/// Renders the RepaintBoundary behind [key] to a PNG.
Future<Uint8List?> capture(GlobalKey key, {double pixelRatio = 3}) async {
  final b = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (b == null) return null;
  final img = await b.toImage(pixelRatio: pixelRatio);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data?.buffer.asUint8List();
}

Future<void> shareCard(GlobalKey key, {required String name, required String text}) async {
  try {
    final png = await capture(key);
    if (png == null) return;
    final f = File('${(await getTemporaryDirectory()).path}/$name.png');
    await f.writeAsBytes(png, flush: true);
    Sfx.play('swoosh');
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'image/png')], text: text));
  } catch (_) {
    toast('Couldn’t share the image');
  }
}

Future<void> saveCard(GlobalKey key, {required String name}) async {
  try {
    final png = await capture(key);
    if (png == null) return;
    if (!await Gal.hasAccess(toAlbum: true)) await Gal.requestAccess(toAlbum: true);
    await Gal.putImageBytes(png, album: 'Shelfwise', name: name);
    Sfx.play('cam');
    toast('Saved to your Photos · Shelfwise album');
  } catch (_) {
    toast('Couldn’t save the image');
  }
}
