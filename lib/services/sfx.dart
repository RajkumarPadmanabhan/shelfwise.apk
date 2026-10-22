import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/store.dart';

/// Little synthesised sound effects (no audio files), ported from the mockup's WebAudio code.
class Sfx {
  static const _rate = 44100;
  static final _cache = <String, String>{};
  static final _players = <String, AudioPlayer>{};
  static bool _ctxSet = false;
  static Directory? _dir;

  static Future<void> play(String key) async {
    if (!store.settings.sounds) return;
    try {
      if (!_ctxSet) {
        _ctxSet = true;
        await AudioPlayer.global.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
      }
      final path = await _file(key);
      final p = _players[key] ??= AudioPlayer();
      await p.stop();
      await p.play(DeviceFileSource(path), mode: PlayerMode.lowLatency, volume: 1);
    } catch (_) {}
  }

  /// Renders every sound once in the background so the first tap isn't late.
  static Future<void> warmUp() async {
    for (final k in _recipes.keys) {
      await _file(k);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  static Future<String> _file(String key) async {
    final hit = _cache[key];
    if (hit != null) return hit;
    _dir ??= await getTemporaryDirectory();
    final f = File('${_dir!.path}/sfx_$key.wav');
    if (!f.existsSync()) await f.writeAsBytes(_render(key), flush: true);
    return _cache[key] = f.path;
  }

  static Uint8List _render(String key) {
    final m = _Mix();
    (_recipes[key] ?? _recipes['bounce']!)(m);
    return m.wav();
  }

  static final Map<String, void Function(_Mix)> _recipes = {
    'tap': (m) => m.tone(520, 380, .08, 'sine', .12),
    'lift': (m) => m.tone(300, 560, .12, 'triangle', .14),
    'drop': (m) => m
      ..tone(200, 90, .14, 'sine', .22)
      ..noise(.05, .1, 'lowpass', 900),
    'tear': (m) {
      for (var i = 0; i < 6; i++) {
        m.noise(.09, .32, 'highpass', 1400.0 + i * 150, 700, i * .06);
      }
      m.noise(.45, .18, 'bandpass', 2200, 500);
    },
    'tape': (m) => m
      ..noise(.35, .22, 'highpass', 2500, 5000)
      ..tone(300, 200, .1, 'square', .05, .3),
    'reset': (m) => m
      ..tone(392, 392, .12, 'triangle', .16)
      ..tone(494, 494, .12, 'triangle', .16, .1)
      ..tone(659, 659, .2, 'triangle', .18, .2),
    'lampon': (m) => m
      ..noise(.03, .25, 'highpass', 2500)
      ..tone(880, 1250, .14, 'sine', .14, .02),
    'lampoff': (m) => m
      ..noise(.03, .25, 'highpass', 2500)
      ..tone(700, 300, .16, 'sine', .14, .02),
    'candleon': (m) {
      m.noise(.4, .2, 'bandpass', 500, 2600);
      for (var j = 0; j < 4; j++) {
        m.noise(.03, .12, 'highpass', 3000, 3000, .25 + j * .07);
      }
    },
    'blow': (m) => m.noise(.45, .28, 'bandpass', 1900, 450),
    'cam': (m) => m
      ..noise(.03, .4, 'highpass', 2200)
      ..noise(.04, .35, 'highpass', 1800, 1800, .09)
      ..tone(1500, 900, .06, 'square', .06, .01),
    'owl': (m) {
      m.tone(430, 360, .28, 'sine', .26);
      m.tone(430, 350, .3, 'sine', .24, .34);
      for (var i = 0; i < 5; i++) {
        m.noise(.12, .2, 'lowpass', 700, 300, .7 + i * .11);
      }
    },
    'clock': (m) {
      for (var q = 0; q < 7; q++) {
        m.tone(1568, 1568, .07, 'triangle', .14, q * .1);
        m.tone(1976, 1976, .07, 'triangle', .1, q * .1 + .05);
      }
    },
    'duck': (m) => m
      ..tone(900, 1600, .1, 'square', .11)
      ..tone(1300, 700, .13, 'square', .11, .12),
    'teddy': (m) => m
      ..tone(480, 700, .11, 'sine', .18)
      ..tone(700, 940, .12, 'sine', .18, .12),
    'trophy': (m) {
      const f = [1046.0, 1318.0, 1568.0, 2093.0];
      for (var i = 0; i < 4; i++) {
        m.tone(f[i], f[i], .35, 'sine', .14, i * .1);
      }
    },
    'globe': (m) => m
      ..noise(.9, .14, 'lowpass', 300, 900)
      ..tone(120, 220, .9, 'sawtooth', .05),
    'hour': (m) => m.noise(1, .09, 'highpass', 3200, 5200),
    'rustle': (m) => m
      ..noise(.4, .12, 'bandpass', 2600, 1800)
      ..noise(.25, .08, 'bandpass', 3200, 2200, .18),
    'knock': (m) => m
      ..tone(260, 190, .09, 'triangle', .22)
      ..tone(240, 170, .09, 'triangle', .2, .13),
    'clink': (m) => m
      ..tone(1900, 1900, .18, 'sine', .12)
      ..tone(2500, 2500, .16, 'sine', .08, .09),
    'check': (m) => m
      ..tone(660, 660, .09, 'triangle', .16)
      ..tone(990, 990, .16, 'triangle', .16, .08),
    'pop': (m) => m.tone(380, 760, .09, 'sine', .16),
    'page': (m) => m
      ..noise(.24, .2, 'bandpass', 900, 3400)
      ..noise(.1, .07, 'highpass', 3200, 5200, .12)
      ..noise(.06, .1, 'lowpass', 500, 300, .2),
    'swoosh': (m) => m.noise(.28, .12, 'bandpass', 600, 2400),
    'bounce': (m) => m
      ..tone(200, 520, .12, 'sine', .2)
      ..tone(520, 230, .2, 'sine', .2, .12),
    'meow': (m) => m
      ..tone(520, 840, .17, 'sawtooth', .18)
      ..tone(840, 430, .34, 'sawtooth', .15, .16),
    'purr': (m) => m.noise(.55, .14, 'lowpass', 240, 180),
    'cat_scare': (m) => m
      ..noise(.4, .25, 'highpass', 2500, 1500)
      ..tone(900, 500, .35, 'sawtooth', .14),
    'bark': (m) => m
      ..tone(320, 170, .14, 'sawtooth', .22)
      ..noise(.07, .15, 'bandpass', 1400, 600)
      ..tone(340, 180, .14, 'sawtooth', .2, .22)
      ..noise(.07, .13, 'bandpass', 1400, 600, .22),
    'dog_pant': (m) => m
      ..noise(.25, .09, 'bandpass', 600, 400)
      ..tone(240, 110, .5, 'sine', .14, .05),
    'dog_scare': (m) => m
      ..tone(1000, 520, .18, 'square', .12)
      ..tone(1050, 560, .18, 'square', .12, .18),
    'thump': (m) => m
      ..tone(130, 50, .12, 'sine', .35)
      ..tone(110, 45, .1, 'sine', .25, .14),
    'rabbit_scare': (m) => m
      ..tone(140, 50, .09, 'sine', .3)
      ..tone(140, 50, .09, 'sine', .3, .1)
      ..tone(1600, 2400, .12, 'sine', .12, .22),
    'chirp': (m) {
      m.tone(2300, 3200, .07, 'sine', .15);
      m.tone(3200, 2600, .05, 'sine', .12, .07);
      m.tone(2500, 3400, .07, 'sine', .14, .15);
    },
    'bird_scare': (m) {
      for (var i = 0; i < 5; i++) {
        m.noise(.05, .15, 'highpass', 3000, 5000, i * .04);
      }
      m.tone(2900, 3600, .08, 'sine', .16, .2);
    },
    'pet_run': (m) {
      for (var i = 0; i < 7; i++) {
        m.noise(.04, .18, 'lowpass', 700, 350, i * .08);
      }
    },
    'pet_land': (m) => m.noise(.08, .25, 'lowpass', 800, 350),
  };

  /// Play pet sound based on species and action
  static void pet(String kind, String action) {
    if (kind == 'none' || kind.isEmpty) return;
    if (action == 'call' || action == 'tap' || action == 'hello') {
      final key = switch (kind) {
        'cat' => 'meow',
        'dog' => 'bark',
        'rabbit' => 'thump',
        'bird' => 'chirp',
        _ => 'tap',
      };
      play(key);
    } else if (action == 'scare') {
      final key = switch (kind) {
        'cat' => 'cat_scare',
        'dog' => 'dog_scare',
        'rabbit' => 'rabbit_scare',
        'bird' => 'bird_scare',
        _ => 'pop',
      };
      play(key);
      Future.delayed(const Duration(milliseconds: 280), () => play('pet_run'));
    } else if (action == 'land') {
      play('pet_land');
    } else if (action == 'sleep') {
      if (kind == 'cat') play('purr');
      if (kind == 'dog') play('dog_pant');
    }
  }

  /// Decoration sounds keyed by gadget, as in the mockup.
  static const decor = {
    'pot': 'rustle', 'cactus': 'rustle', 'succ': 'rustle', 'vase': 'rustle', 'frame': 'knock', 'pens': 'knock',
    'scope': 'knock', 'teddy': 'teddy', 'globe': 'globe', 'clock': 'clock', 'hour': 'hour', 'duck': 'duck',
    'trophy': 'trophy', 'cup': 'clink', 'cam': 'cam', 'owl': 'owl',
  };
}

/// Haptic taps that respect the user's setting.
class Buzz {
  static void tick() {
    if (store.settings.haptics) HapticFeedback.selectionClick();
  }

  static void light() {
    if (store.settings.haptics) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (store.settings.haptics) HapticFeedback.mediumImpact();
  }

  static Future<void> rip() async {
    if (!store.settings.haptics) return;
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 65));
    HapticFeedback.mediumImpact();
  }
}

/// A tiny offline mixer: oscillators and filtered noise with exponential ramps.
class _Mix {
  final List<double> buf = [];
  final _r = Random(7);

  void _ensure(int n) {
    while (buf.length < n) {
      buf.add(0);
    }
  }

  static double _exp(double a, double b, double t) => a * pow(b / a, t.clamp(0.0, 1.0));

  double _env(double t, double dur, double vol, double attack) {
    if (t < 0 || t > dur) return 0;
    if (t < attack) return _exp(.0001, vol, t / attack);
    return _exp(vol, .0001, (t - attack) / (dur - attack));
  }

  void tone(double f1, double f2, double dur, String type, double vol, [double delay = 0]) {
    const sr = Sfx._rate;
    final start = (delay * sr).round();
    final n = ((dur + .03) * sr).round();
    _ensure(start + n);
    final attack = min(.015, dur / 3);
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final f = f2 == f1 ? f1 : _exp(f1, f2, t / dur);
      phase += f / sr;
      phase -= phase.floorToDouble();
      final double s = switch (type) {
        'square' => phase < .5 ? 1 : -1,
        'triangle' => 1 - 4 * (phase - .5).abs(),
        'sawtooth' => 2 * phase - 1,
        _ => sin(2 * pi * phase),
      };
      buf[start + i] += s * _env(t, dur, vol, attack);
    }
  }

  void noise(double dur, double vol, String type, double f1, [double? f2, double delay = 0]) {
    const sr = Sfx._rate;
    final start = (delay * sr).round();
    final n = ((dur + .02) * sr).round();
    _ensure(start + n);
    final attack = min(.02, dur / 3);
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
    var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      if (i % 32 == 0) {
        final f = (f2 == null || f2 == f1 ? f1 : _exp(f1, f2, t / dur)).clamp(20.0, sr / 2 - 100);
        final w0 = 2 * pi * f / sr, cw = cos(w0), alpha = sin(w0) / 2; // Q = 1
        final a0 = 1 + alpha;
        switch (type) {
          case 'lowpass':
            b0 = (1 - cw) / 2 / a0;
            b1 = (1 - cw) / a0;
            b2 = b0;
          case 'highpass':
            b0 = (1 + cw) / 2 / a0;
            b1 = -(1 + cw) / a0;
            b2 = b0;
          default:
            b0 = alpha / a0;
            b1 = 0;
            b2 = -alpha / a0;
        }
        a1 = -2 * cw / a0;
        a2 = (1 - alpha) / a0;
      }
      final x = _r.nextDouble() * 2 - 1;
      final y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1;
      x1 = x;
      y2 = y1;
      y1 = y;
      buf[start + i] += y * _env(t, dur, vol, attack);
    }
  }

  Uint8List wav() {
    const sr = Sfx._rate;
    final n = buf.length;
    final out = ByteData(44 + n * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        out.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    out.setUint32(4, 36 + n * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little);
    out.setUint16(22, 1, Endian.little);
    out.setUint32(24, sr, Endian.little);
    out.setUint32(28, sr * 2, Endian.little);
    out.setUint16(32, 2, Endian.little);
    out.setUint16(34, 16, Endian.little);
    str(36, 'data');
    out.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      out.setInt16(44 + i * 2, (buf[i].clamp(-1.0, 1.0) * 32000).round(), Endian.little);
    }
    return out.buffer.asUint8List();
  }
}
