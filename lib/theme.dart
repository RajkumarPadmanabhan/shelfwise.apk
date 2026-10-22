import 'dart:ui';

import 'package:flutter/material.dart';

/// One complete set of surface/text colours (light or dark).
class Pal {
  final Brightness brightness;
  final Color page, bg, ink, muted, chip, chipText, card, line, inputLine, softBrown, body, toast, dangerBg, dangerInk,
      error, track, switchOff, plank, field, nav, hint;
  const Pal({
    required this.brightness,
    required this.page,
    required this.bg,
    required this.ink,
    required this.muted,
    required this.chip,
    required this.chipText,
    required this.card,
    required this.line,
    required this.inputLine,
    required this.softBrown,
    required this.body,
    required this.toast,
    required this.dangerBg,
    required this.dangerInk,
    required this.error,
    required this.track,
    required this.switchOff,
    required this.plank,
    required this.field,
    required this.nav,
    required this.hint,
  });
}

/// The mockup's cream palette.
const lightPal = Pal(
  brightness: Brightness.light,
  page: Color(0xFFE6E1DA),
  bg: Color(0xFFF9EDD9),
  ink: Color(0xFF3A2A1C),
  muted: Color(0xFF7D6F62),
  chip: Color(0xFFEEDFC9),
  chipText: Color(0xFF6D5C4B),
  card: Color(0xFFFFF8EC),
  line: Color(0xFFE8D8BF),
  inputLine: Color(0xFFE0CDB0),
  softBrown: Color(0xFFF1E3CD),
  body: Color(0xFF5D4B3B),
  toast: Color(0xFF2B1D10),
  dangerBg: Color(0xFFF6D4CC),
  dangerInk: Color(0xFF8E2A16),
  error: Color(0xFFA3321C),
  track: Color(0xFFDCCBB0),
  switchOff: Color(0xFFD5C6AE),
  plank: Color(0xFFB79A72),
  field: Color(0xFFFFFFFF),
  nav: Color.fromRGBO(249, 237, 217, .88),
  hint: Color(0xFFA89A8A),
);

/// A warm "reading lamp at night" palette.
const darkPal = Pal(
  brightness: Brightness.dark,
  page: Color(0xFF120E0A),
  bg: Color(0xFF1C1611),
  ink: Color(0xFFF3EAD9),
  muted: Color(0xFFB2A290),
  chip: Color(0xFF342A21),
  chipText: Color(0xFFE3D4BF),
  card: Color(0xFF261F18),
  line: Color(0xFF3A2F25),
  inputLine: Color(0xFF4A3C2F),
  softBrown: Color(0xFF332719),
  body: Color(0xFFD9CAB5),
  toast: Color(0xFF3B2E22),
  dangerBg: Color(0xFF4A231C),
  dangerInk: Color(0xFFFFB4A8),
  error: Color(0xFFFF8A70),
  track: Color(0xFF4A3C2F),
  switchOff: Color(0xFF55483A),
  plank: Color(0xFF6E5230),
  field: Color(0xFF2E251D),
  nav: Color.fromRGBO(28, 22, 17, .9),
  hint: Color(0xFF8C7C6A),
);

/// A background colour family. Each has a light and a dark version, derived from
/// the cream palettes by shifting hue and saturation.
class BgFamily {
  final String key, name;
  final double? hue; // null keeps the cream palette's own hues
  final double sat; // saturation multiplier
  const BgFamily(this.key, this.name, this.hue, this.sat);
}

const bgFamilies = [
  BgFamily('cream', 'Cream', null, 1),
  BgFamily('paper', 'Paper', null, .18),
  BgFamily('sage', 'Sage', 105, .85),
  BgFamily('sky', 'Sky', 210, .9),
  BgFamily('blush', 'Blush', 350, .8),
  BgFamily('lavender', 'Lavender', 268, .8),
];

Color _tint(Color c, BgFamily f) {
  if (f.hue == null && f.sat == 1) return c;
  final h = HSLColor.fromColor(c);
  return h.withHue(f.hue ?? h.hue).withSaturation((h.saturation * f.sat).clamp(0.0, 1.0)).toColor();
}

final _palCache = <String, Pal>{};

/// The palette for background family [key] in light or [dark] mode.
Pal palFor(String key, bool dark) => _palCache.putIfAbsent('$key|$dark', () {
      final f = bgFamilies.firstWhere((b) => b.key == key, orElse: () => bgFamilies.first);
      final p = dark ? darkPal : lightPal;
      Color t(Color c) => _tint(c, f);
      return Pal(
        brightness: p.brightness,
        page: t(p.page),
        bg: t(p.bg),
        ink: t(p.ink),
        muted: t(p.muted),
        chip: t(p.chip),
        chipText: t(p.chipText),
        card: t(p.card),
        line: t(p.line),
        inputLine: t(p.inputLine),
        softBrown: t(p.softBrown),
        body: t(p.body),
        toast: t(p.toast),
        dangerBg: p.dangerBg,
        dangerInk: p.dangerInk,
        error: p.error,
        track: t(p.track),
        switchOff: t(p.switchOff),
        plank: p.plank,
        field: p.field == const Color(0xFFFFFFFF) ? p.field : t(p.field),
        nav: t(p.nav),
        hint: t(p.hint),
      );
    });

/// Subtle patterns drawn behind the pages.
const bgPatterns = [('none', 'Plain'), ('dots', 'Dots'), ('ruled', 'Ruled'), ('grid', 'Grid'), ('linen', 'Linen')];

class PatternPainter extends CustomPainter {
  final String kind;
  final Color color;
  const PatternPainter(this.kind, this.color);

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    switch (kind) {
      case 'dots':
        for (double y = 10; y < s.height; y += 22) {
          final off = ((y / 22).floor().isOdd) ? 11.0 : 0.0;
          for (double x = 10 + off; x < s.width; x += 22) {
            c.drawCircle(Offset(x, y), 1.6, p);
          }
        }
      case 'ruled':
        for (double y = 34; y < s.height; y += 30) {
          c.drawLine(Offset(0, y), Offset(s.width, y), p);
        }
        c.drawLine(const Offset(30, 0), Offset(30, s.height), p..color = const Color(0x33E0703F));
      case 'grid':
        for (double y = 0; y < s.height; y += 24) {
          c.drawLine(Offset(0, y), Offset(s.width, y), p);
        }
        for (double x = 0; x < s.width; x += 24) {
          c.drawLine(Offset(x, 0), Offset(x, s.height), p);
        }
      case 'linen':
        p.strokeWidth = .8;
        for (double d = -s.height; d < s.width; d += 9) {
          c.drawLine(Offset(d, 0), Offset(d + s.height, s.height), p);
        }
        for (double d = 0; d < s.width + s.height; d += 9) {
          c.drawLine(Offset(d, 0), Offset(d - s.height, s.height), p..color = color.withValues(alpha: color.a * .6));
        }
    }
  }

  @override
  bool shouldRepaint(PatternPainter o) => o.kind != kind || o.color != color;
}

class Accent {
  final String name;
  final Color color;
  const Accent(this.name, this.color);
}

const accents = [
  Accent('Cinnamon', Color(0xFFB8692A)),
  Accent('Forest', Color(0xFF3F7D5C)),
  Accent('Plum', Color(0xFF8A5A9E)),
  Accent('Ocean', Color(0xFF2F6F8F)),
  Accent('Rose', Color(0xFFC0566E)),
];

/// Current colours. Surface colours follow light/dark; [brown] is the chosen accent.
class C {
  static Pal p = lightPal;
  static Color accent = accents.first.color;
  static bool get dark => p.brightness == Brightness.dark;

  static Color get page => p.page;
  static Color get bg => p.bg;
  static Color get ink => p.ink;
  static Color get muted => p.muted;
  static Color get brown => accent;
  static Color get chip => p.chip;
  static Color get chipText => p.chipText;
  static Color get card => p.card;
  static Color get line => p.line;
  static Color get inputLine => p.inputLine;
  static Color get softBrown => p.softBrown;
  static Color get body => p.body;
  static Color get toast => p.toast;
  static Color get dangerBg => p.dangerBg;
  static Color get dangerInk => p.dangerInk;
  static Color get error => p.error;
  static Color get track => p.track;
  static Color get switchOff => p.switchOff;
  static Color get plank => p.plank;
  static Color get field => p.field;
  static Color get nav => p.nav;
  static Color get hint => p.hint;

  // welcome / intro screens keep the mockup's fixed look
  static const cream = Color(0xFFF7F0E6);
  static const black = Color(0xFF171717);
  static const orange = Color(0xFFF26A21);
  static const introPage = Color(0xFFE9E5DF);
}

class F {
  static const nunito = 'Nunito';
  static const serif = 'Playfair';
  static const hand = 'Caveat';
  static const sans = 'Inter';
  static const lora = 'Lora';

  /// The interface font the person picked.
  static String ui = nunito;
}

const fontChoices = [('Nunito', 'Rounded'), ('Inter', 'Clean'), ('Lora', 'Bookish')];

/// Shorthand for Nunito text styles, which nearly every widget uses.
TextStyle nu(double size, FontWeight w, [Color? color, double? height]) =>
    TextStyle(fontFamily: F.ui, fontSize: size, fontWeight: w, color: color ?? C.ink, height: height);

const ease = Cubic(.2, .8, .2, 1);
const popCurve = Cubic(.3, 1.6, .5, 1);
const springCurve = Cubic(.3, 1.4, .5, 1);

/// Book cover colours: [background, text, optional top border].
const coverPalette = <List<Color>>[
  [Color(0xFF1E1A14), Color(0xFFE9DCC0)],
  [Color(0xFFD9C493), Color(0xFF2A2018)],
  [Color(0xFFF6EFE2), Color(0xFF2A2018), Color(0xFFC63A2A)],
  [Color(0xFFF26B2A), Color(0xFFFFFFFF)],
  [Color(0xFFE9D9A8), Color(0xFF2A2018)],
  [Color(0xFF35302D), Color(0xFFEEEEEE)],
  [Color(0xFFE5E85A), Color(0xFF111111), Color(0xFF7BBD7A)],
  [Color(0xFFE9A07A), Color(0xFF2A2018)],
  [Color(0xFFF6B3C3), Color(0xFF2A2018)],
  [Color(0xFF8F9F80), Color(0xFF171717)],
  [Color(0xFF1B2A44), Color(0xFFF6EAD2)],
  [Color(0xFFC9372C), Color(0xFFFFFFFF)],
];

/// Same string hash as the mockup (h*31+c mod 360) so titles keep their colours.
int hue(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) % 360;
  }
  return h;
}

List<Color> coverFor(String title) => coverPalette[hue(title) % coverPalette.length];

/// Shelf "glass" gradients: g1, g2, g3, dot colour.
const shelfPalettes = <List<Color>>[
  [Color.fromRGBO(255, 170, 190, .7), Color.fromRGBO(255, 160, 150, .75), Color.fromRGBO(255, 230, 160, .8), Color(0xFFF48AA0)],
  [Color.fromRGBO(215, 170, 235, .8), Color.fromRGBO(190, 160, 235, .8), Color.fromRGBO(150, 205, 240, .85), Color(0xFFB58BE0)],
  [Color.fromRGBO(170, 225, 190, .8), Color.fromRGBO(150, 215, 200, .8), Color.fromRGBO(190, 230, 240, .85), Color(0xFF5FBF9A)],
  [Color.fromRGBO(255, 205, 150, .8), Color.fromRGBO(255, 185, 140, .8), Color.fromRGBO(255, 225, 170, .85), Color(0xFFF2A04A)],
];

/// To-do bento tile colours (the mockup's vivid post tiles): bg, fg, border?.
class TileColors {
  final Color bg, fg;
  final Color? border;
  final bool dark;
  const TileColors(this.bg, this.fg, {this.border, this.dark = false});
}

const tileColors = <TileColors>[
  TileColors(Color(0xFFFF4F0F), Color(0xFF111111)),
  TileColors(Color(0xFFF5ECDF), Color(0xFF111111), border: Color(0x1A000000)),
  TileColors(Color(0xFFF6B300), Color(0xFF111111)),
  TileColors(Color(0xFFB6D8D5), Color(0xFF111111)),
  TileColors(Color(0xFF1D4A37), Color(0xFFFFFFFF), dark: true),
  TileColors(Color(0xFF1C1C1C), Color(0xFFFFFFFF), border: Color(0xFF333333), dark: true),
];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.brown,
    brightness: C.p.brightness,
    primary: C.brown,
    onPrimary: Colors.white,
    surface: C.card,
    onSurface: C.ink,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: C.p.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    fontFamily: F.ui,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: C.brown,
      selectionColor: C.brown.withValues(alpha: .33),
      selectionHandleColor: C.brown,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: C.card,
      headerBackgroundColor: C.brown,
      headerForegroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: C.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );
}

/// Blur helper used by the nav bar.
ImageFilter blur(double s) => ImageFilter.blur(sigmaX: s, sigmaY: s);
