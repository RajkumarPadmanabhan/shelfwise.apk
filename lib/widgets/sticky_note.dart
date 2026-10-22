import 'dart:math';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../services/sfx.dart';
import '../theme.dart';
import 'common.dart';
import 'dialogs.dart';

/// Palette colors from notes.html
const stickyColorDefs = <String, Color>{
  '#ffe27a': Color(0xFFFFE27A), // Yellow
  '#f8b4c6': Color(0xFFF8B4C6), // Pink
  '#bfe3b0': Color(0xFFBFE3B0), // Mint
  '#a8d4f2': Color(0xFFA8D4F2), // Blue
  '#ffbe85': Color(0xFFFFBE85), // Orange
  '#d3c2f1': Color(0xFFD3C2F1), // Lilac
};

/// Ink pen colors from notes.html
const stickyInkDefs = <String, Color>{
  '#1c2f6b': Color(0xFF1C2F6B), // Blue pen
  '#171717': Color(0xFF171717), // Black pen
  '#c62828': Color(0xFFC62828), // Red pen
  '#2e7d32': Color(0xFF2E7D32), // Green pen
};

Color parseStickyColor(String hex) =>
    stickyColorDefs[hex.toLowerCase()] ??
    Color(int.tryParse(hex.replaceFirst('#', '0xFF')) ?? 0xFFFFE27A);

Color parseStickyInk(String hex) =>
    stickyInkDefs[hex.toLowerCase()] ??
    Color(int.tryParse(hex.replaceFirst('#', '0xFF')) ?? 0xFF1C2F6B);

/// Interactive fluttering sticky note widget (inspired by notes.html).
/// Features:
/// - 3D perspective paper flutter animation.
/// - Top tape band with a red pushpin / thumbtack (hidden when [showPin] is false).
/// - Realistic multi-layered paper drop shadows.
/// - Dynamic tilt while dragging.
/// - Paper rip tear animation with sound.
/// - Customizable size: Small ('s'), Medium ('m'), Large ('l').
/// - Tap to view/edit text, paper color, ink color, and size.
class StickyNoteWidget extends StatefulWidget {
  final StickyNote note;
  final double width;
  final double minHeight;
  final bool enableDrag;
  final bool canEdit;
  final bool showPin;
  final VoidCallback? onTear;
  final void Function(double dx, double dy)? onMoved;
  final VoidCallback? onEdited;

  const StickyNoteWidget({
    super.key,
    required this.note,
    this.width = 138,
    this.minHeight = 112,
    this.enableDrag = true,
    this.canEdit = true,
    this.showPin = true,
    this.onTear,
    this.onMoved,
    this.onEdited,
  });

  @override
  State<StickyNoteWidget> createState() => _StickyNoteWidgetState();
}

class _StickyNoteWidgetState extends State<StickyNoteWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 5500 + Random().nextInt(2000)),
  )..repeat();

  bool _isDragging = false;
  double _dragVx = 0.0;
  bool _isTorn = false;

  double get effectiveWidth {
    switch (widget.note.size) {
      case 's':
        return 110.0;
      case 'l':
        return 176.0;
      case 'm':
      default:
        return widget.width;
    }
  }

  double get effectiveMinHeight {
    switch (widget.note.size) {
      case 's':
        return 90.0;
      case 'l':
        return 144.0;
      case 'm':
      default:
        return widget.minHeight;
    }
  }

  double get effectiveFontScale {
    switch (widget.note.size) {
      case 's':
        return 0.85;
      case 'l':
        return 1.22;
      case 'm':
      default:
        return 1.0;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _tearNote() {
    if (_isTorn) return;
    setState(() => _isTorn = true);
    Sfx.play('tear');
    Buzz.medium();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) widget.onTear?.call();
    });
  }

  void _openEditor() {
    Buzz.tick();
    openDialog((ctx) => _StickyNoteEditorDialog(
          note: widget.note,
          onSave: (text, color, ink, size) {
            setState(() {
              widget.note.text = text;
              widget.note.color = color;
              widget.note.ink = ink;
              widget.note.size = size;
            });
            widget.onEdited?.call();
          },
          onTear: _tearNote,
        ));
  }

  void _openViewOrTearDialog() {
    Buzz.tick();
    openDialog((ctx) {
      final paperColor = parseStickyColor(widget.note.color);
      final inkColor = parseStickyInk(widget.note.ink);
      final fontScale = effectiveFontScale;
      return AppDialog(
        title: 'Sticky Note 📌',
        maxWidth: 340,
        actions: [
          const Btn('Close'),
          Btn('Tear off 🗑️', kind: Kind.dng, onTap: () {
            _tearNote();
            return true;
          }),
        ],
        children: [
          Container(
            padding: EdgeInsets.all(14 * fontScale),
            decoration: BoxDecoration(
              color: paperColor,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  offset: Offset(0, 3),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Text(
              widget.note.text.trim().isEmpty ? '(Empty note)' : widget.note.text,
              style: TextStyle(
                fontFamily: 'Caveat',
                fontSize: 19 * fontScale,
                fontWeight: FontWeight.w700,
                color: inkColor,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Sticky notes can be edited in the Library shelf. You can tear off or delete this note from Home anytime.',
            style: nu(12, FontWeight.w600, C.muted),
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final curW = effectiveWidth;
    final curH = effectiveMinHeight;

    if (_isTorn) {
      // Split tear animation: paper rips into halves that drift away
      return SizedBox(
        width: curW,
        height: curH,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeIn,
          builder: (_, t, _) {
            final paperColor = parseStickyColor(widget.note.color);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Left half falling left & down
                Positioned(
                  left: -18 * t,
                  top: 26 * t,
                  width: curW * 0.52,
                  height: curH,
                  child: Transform.rotate(
                    angle: -0.18 * t,
                    child: Opacity(
                      opacity: (1.0 - t).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: paperColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            bottomLeft: Radius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Right half falling right & down
                Positioned(
                  right: -18 * t,
                  top: 32 * t,
                  width: curW * 0.52,
                  height: curH,
                  child: Transform.rotate(
                    angle: 0.22 * t,
                    child: Opacity(
                      opacity: (1.0 - t).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: paperColor,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(3),
                            bottomRight: Radius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    final paperColor = parseStickyColor(widget.note.color);
    final inkColor = parseStickyInk(widget.note.ink);
    final fontScale = effectiveFontScale;

    return GestureDetector(
      onTap: widget.canEdit ? _openEditor : _openViewOrTearDialog,
      onDoubleTap: _tearNote,
      onPanStart: widget.enableDrag
          ? (_) {
              setState(() {
                _isDragging = true;
                _dragVx = 0.0;
              });
              Buzz.light();
            }
          : null,
      onPanUpdate: widget.enableDrag
          ? (details) {
              setState(() {
                _dragVx = (_dragVx * 0.6 + (details.delta.dx * 0.4)).clamp(-15.0, 15.0);
              });
              widget.onMoved?.call(details.delta.dx, details.delta.dy);
            }
          : null,
      onPanEnd: widget.enableDrag
          ? (_) {
              setState(() {
                _isDragging = false;
                _dragVx = 0.0;
              });
            }
          : null,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          // 3D paper flutter animation
          final val = _anim.value;
          final flutterX = _isDragging ? 0.0 : sin(val * 2 * pi) * 0.06;
          final flutterY = _isDragging ? 0.0 : cos(val * 2 * pi) * 0.04;
          final currentRot = (widget.note.r + _dragVx * 0.8) * pi / 180;

          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.0016)
            ..rotateX(flutterX)
            ..rotateY(flutterY)
            ..rotateZ(currentRot);

          return Transform(
            transform: transform,
            alignment: Alignment.topCenter,
            child: child,
          );
        },
        child: Container(
          width: curW,
          constraints: BoxConstraints(minHeight: curH),
          decoration: BoxDecoration(
            color: paperColor,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: const Color.fromRGBO(0, 0, 0, 0.10),
                offset: const Offset(0, 1),
                blurRadius: 1,
              ),
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, _isDragging ? 0.32 : 0.20),
                offset: Offset(0, _isDragging ? 16 : 10),
                blurRadius: _isDragging ? 20 : 14,
                spreadRadius: -4,
              ),
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, _isDragging ? 0.22 : 0.12),
                offset: Offset(0, _isDragging ? 24 : 16),
                blurRadius: _isDragging ? 28 : 22,
                spreadRadius: -8,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Tape strip with red pushpin
              _TapeWithPin(paperColor: paperColor, height: (24 * fontScale).clamp(20.0, 28.0), showPin: widget.showPin),

              // Note handwritten body
              Padding(
                padding: EdgeInsets.fromLTRB(10 * fontScale, 6 * fontScale, 10 * fontScale, 14 * fontScale),
                child: Text(
                  widget.note.text.trim().isEmpty
                      ? 'Write something…'
                      : widget.note.text,
                  style: TextStyle(
                    fontFamily: 'Caveat',
                    fontSize: 16.5 * fontScale,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: widget.note.text.trim().isEmpty
                        ? inkColor.withValues(alpha: 0.45)
                        : inkColor,
                  ),
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Semi-transparent tape with central 3D pushpin / thumbtack
class _TapeWithPin extends StatelessWidget {
  final Color paperColor;
  final double height;
  final bool showPin;
  const _TapeWithPin({required this.paperColor, this.height = 24, this.showPin = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.42),
        border: const Border(
          bottom: BorderSide(color: Color(0x24000000), width: 1),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            offset: Offset(0, 2),
            blurRadius: 2,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: !showPin ? null : Container(
        width: (height * 0.54).clamp(10.0, 15.0),
        height: (height * 0.54).clamp(10.0, 15.0),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(-0.35, -0.35),
            radius: 0.8,
            colors: [
              Color(0xFFFF9A85),
              Color(0xFFD6402B),
              Color(0xFF8E1B0D),
            ],
            stops: [0.0, 0.65, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x55000000),
              offset: Offset(0, 2),
              blurRadius: 2.5,
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal dialog for editing note text, selecting size, paper color, or tearing it off.
class _StickyNoteEditorDialog extends StatefulWidget {
  final StickyNote note;
  final void Function(String text, String color, String ink, String size) onSave;
  final VoidCallback onTear;

  const _StickyNoteEditorDialog({
    required this.note,
    required this.onSave,
    required this.onTear,
  });

  @override
  State<_StickyNoteEditorDialog> createState() => _StickyNoteEditorDialogState();
}

class _StickyNoteEditorDialogState extends State<_StickyNoteEditorDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.note.text);
  late String _color = widget.note.color;
  late String _ink = widget.note.ink;
  late String _size = widget.note.size;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curColor = parseStickyColor(_color);
    final curInk = parseStickyInk(_ink);

    return AppDialog(
      title: 'Sticky note',
      maxWidth: 370,
      actions: [
        Btn(
          'Tear off ✂',
          kind: Kind.dng,
          onTap: () {
            Navigator.of(context).pop();
            widget.onTear();
            return false;
          },
        ),
        Btn(
          'Done',
          kind: Kind.pri,
          onTap: () {
            widget.onSave(_ctrl.text.trim(), _color, _ink, _size);
            toast('Note updated');
            return true;
          },
        ),
      ],
      children: [
        // Note Preview & Input Field
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: curColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                offset: Offset(0, 4),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ctrl,
                maxLines: 4,
                maxLength: 240,
                autofocus: widget.note.text.isEmpty,
                style: TextStyle(
                  fontFamily: 'Caveat',
                  fontSize: _size == 'l' ? 20 : (_size == 's' ? 16 : 18),
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: curInk,
                ),
                decoration: InputDecoration(
                  hintText: 'Write a reading thought, quote or reminder…',
                  hintStyle: TextStyle(
                    fontFamily: 'Caveat',
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: curInk.withValues(alpha: 0.45),
                  ),
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Size Selector
        Text('Note size', style: nu(13, FontWeight.w800, C.chipText)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (sz, label) in const [
              ('s', 'S Small'),
              ('m', 'M Medium'),
              ('l', 'L Large'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Pressable(
                  onTap: () {
                    Buzz.tick();
                    setState(() => _size = sz);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: _size == sz ? C.brown : C.chip,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _size == sz ? C.brown : const Color(0x33000000),
                        width: _size == sz ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      label,
                      style: nu(12.5, FontWeight.w800, _size == sz ? Colors.white : C.chipText),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),

        // Color Swatches from notes.html
        Text('Paper color', style: nu(13, FontWeight.w800, C.chipText)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final entry in stickyColorDefs.entries)
              GestureDetector(
                onTap: () {
                  Buzz.tick();
                  setState(() => _color = entry.key);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: entry.value,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _color.toLowerCase() == entry.key
                          ? C.brown
                          : const Color(0x33000000),
                      width: _color.toLowerCase() == entry.key ? 2.5 : 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x18000000),
                        offset: Offset(1, 2),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  child: _color.toLowerCase() == entry.key
                      ? const Center(
                          child: Icon(Icons.check, size: 18, color: Color(0xFF2B2B2B)))
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),

        // Ink Swatches from notes.html
        Text('Pen ink', style: nu(13, FontWeight.w800, C.chipText)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final entry in stickyInkDefs.entries)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () {
                    Buzz.tick();
                    setState(() => _ink = entry.key);
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: entry.value,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _ink.toLowerCase() == entry.key
                              ? C.brown.withValues(alpha: 0.9)
                              : const Color(0x44000000),
                          blurRadius: _ink.toLowerCase() == entry.key ? 6 : 2,
                          spreadRadius: _ink.toLowerCase() == entry.key ? 1.5 : 0,
                        ),
                      ],
                    ),
                    child: _ink.toLowerCase() == entry.key
                        ? const Center(
                            child: Icon(Icons.check, size: 14, color: Colors.white))
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
