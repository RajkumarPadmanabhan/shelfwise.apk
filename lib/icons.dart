import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Stroke icons from the mockup (24x24 viewBox, currentColor strokes).
class Ic {
  static const home = '<path d="M3 11l9-8 9 8v10H3z"/><path d="M10 21v-6h4v6"/>';
  static const library =
      '<rect x="3" y="6" width="4" height="15" rx="1"/><rect x="9" y="3" width="4" height="18" rx="1"/><rect x="15" y="7" width="4" height="14" rx="1" transform="rotate(-12 17 14)"/>';
  static const todo =
      '<rect x="4" y="3" width="16" height="18" rx="2.5"/><path d="M8 8.5l1.6 1.6L12.5 7M8 14.5l1.6 1.6 2.9-3.1M15 8.5h2M15 14.5h2"/>';
  static const stats =
      '<rect x="3" y="11" width="5" height="10" rx="1"/><rect x="9.5" y="3" width="5" height="18" rx="1"/><rect x="16" y="8" width="5" height="13" rx="1"/>';
  static const settings =
      '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>';
  static const bell = '<path d="M6 9a6 6 0 0 1 12 0c0 6 2 7 2 7H4s2-1 2-7zM10 20a2 2 0 0 0 4 0"/>';
  static const gift =
      '<rect x="3" y="8" width="18" height="4"/><path d="M5 12v9h14v-9M12 8v13M12 8c-3 0-5-4-2-4s2 4 2 4zm0 0c3 0 5-4 2-4s-2 4-2 4z"/>';
  static const expand = '<path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7"/>';
  static const fullscreen = '<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>';
  static const camera = '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>';
  static const pencil = '<path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>';
  static const plus = '<path d="M12 5v14M5 12h14"/>';
  static const read =
      '<path d="M2 5.5C5 4 8.5 4 12 6c3.5-2 7-2 10-.5V19c-3-1.5-6.5-1.5-10 .5-3.5-2-7-2-10-.5z"/><path d="M12 6v13.5"/>';
  static const done = '<circle cx="12" cy="12" r="9"/><path d="M8 12.5l3 3 5-6"/>';
  static const move = '<path d="M4 7h14M14 3l4 4-4 4M20 17H6M10 13l-4 4 4 4"/>';
  static const edit = '<path d="M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>';
  static const noImg =
      '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.5"/><path d="M21 16l-5-5-8 9M3 3l18 18"/>';
  static const trash = '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>';
  static const check = '<circle cx="12" cy="12" r="9"/><path d="M8 12.5l3 3 5-6"/>';
  static const star = '<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z"/>';
  static const clock = '<circle cx="12" cy="13" r="8"/><path d="M12 9v4l3 2M5 3L2 6M19 3l3 3"/>';
  static const share = '<path d="M4 12v7a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-7M16 6l-4-4-4 4M12 2v13"/>';
  static const download = '<path d="M4 15v4a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-4M7 10l5 5 5-5M12 15V3"/>';
  static const explore =
      '<circle cx="12" cy="12" r="10"/><polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76"/>';
  static const heart =
      '<path d="M12 21s-8-5.2-8-11a4.6 4.6 0 0 1 8-3 4.6 4.6 0 0 1 8 3c0 5.8-8 11-8 11z"/>';
  static const bookmark = '<path d="M6 3h12v18l-6-4.5L6 21z"/>';
  static const list = '<path d="M4 6h16M4 12h16M4 18h16"/>';
  static const grid =
      '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>';
  static const search = '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>';
  static const close = '<path d="M18 6L6 18M6 6l12 12"/>';
}

/// Renders one of the [Ic] stroke icons in [color].
class SvgIcon extends StatelessWidget {
  final String body;
  final double size;
  final Color color;
  final double stroke;
  final Color? fill;
  const SvgIcon(this.body, {super.key, this.size = 22, required this.color, this.stroke = 2, this.fill});

  @override
  Widget build(BuildContext context) {
    final hex = _hex(color);
    final f = fill == null ? 'none' : _hex(fill!);
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="$f" stroke="$hex" stroke-width="$stroke" '
      'stroke-linecap="round" stroke-linejoin="round">$body</svg>',
      width: size,
      height: size,
    );
  }
}

String _hex(Color c) {
  final v = c.toARGB32();
  final rgb = (v & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final a = (v >> 24) & 0xFF;
  return a == 0xFF ? '#$rgb' : 'rgba(${(v >> 16) & 0xFF},${(v >> 8) & 0xFF},${v & 0xFF},${(a / 255).toStringAsFixed(3)})';
}
