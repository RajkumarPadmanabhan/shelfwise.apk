import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../widgets/common.dart';

/// Global service controlling shelf CD music playback and sync with UI rotation.
class ShelfCdPlayer extends ChangeNotifier {
  ShelfCdPlayer._() {
    _init();
  }
  static final ShelfCdPlayer I = ShelfCdPlayer._();

  final AudioPlayer _player = AudioPlayer();
  String? currentCdId;
  String? currentTitle;
  bool isPlaying = false;

  void _init() {
    _player.onPlayerStateChanged.listen((state) {
      final playing = state == PlayerState.playing;
      if (isPlaying != playing) {
        isPlaying = playing;
        notifyListeners();
      }
    });

    _player.onPlayerComplete.listen((_) {
      isPlaying = false;
      notifyListeners();
    });
  }

  bool isCdPlaying(String cdId) => isPlaying && currentCdId == cdId;

  Future<void> togglePlay(ShelfCd cd) async {
    final fileName = cd.audioFile;
    if (fileName == null || fileName.isEmpty) {
      toast('No song uploaded to this CD yet! 💿');
      return;
    }

    final file = store.audioFile(fileName);
    if (!file.existsSync()) {
      toast('Song audio file not found on device');
      return;
    }

    if (currentCdId == cd.id && isPlaying) {
      await _player.pause();
      isPlaying = false;
      notifyListeners();
      return;
    }

    try {
      if (currentCdId != cd.id) {
        await _player.stop();
      }
      currentCdId = cd.id;
      currentTitle = cd.title ?? 'CD Track';
      await _player.play(DeviceFileSource(file.path));
      isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Shelfwise: could not play audio: $e');
      toast('Could not play audio track');
      isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> stopIfPlaying(String cdId) async {
    if (currentCdId == cdId) {
      try {
        await _player.stop();
      } catch (_) {}
      currentCdId = null;
      currentTitle = null;
      isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    isPlaying = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
