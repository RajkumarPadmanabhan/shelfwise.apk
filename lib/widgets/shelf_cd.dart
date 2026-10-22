import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../services/cd_player.dart';
import '../services/sfx.dart';
import '../theme.dart';
import 'common.dart';
import 'dialogs.dart';

/// Interactive Compact Disc (CD) widget displayed on the shelf.
/// Features:
/// - Iridescent holographic reflective disc styling with vinyl/laser grooves.
/// - Continuous rotation animation while playing audio (`cd rotates whil playing`).
/// - Tap to play/stop from Home.
/// - Tap in Library to upload/manage an MP3 audio track.
/// - Floating musical notes micro-animation while playing.
/// - Free shelf dragging to reposition.
/// - Deleting or tearing permanently deletes the uploaded MP3 file.
class ShelfCdWidget extends StatefulWidget {
  final ShelfCd cd;
  final bool home;
  final void Function(double dx, double dy)? onMoved;
  final VoidCallback? onTear;
  final VoidCallback? onUploadSong;

  const ShelfCdWidget({
    super.key,
    required this.cd,
    required this.home,
    this.onMoved,
    this.onTear,
    this.onUploadSong,
  });

  @override
  State<ShelfCdWidget> createState() => _ShelfCdWidgetState();
}

class _ShelfCdWidgetState extends State<ShelfCdWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  bool _isDragging = false;
  double _dragVx = 0.0;
  bool _isTorn = false;

  @override
  void initState() {
    super.initState();
    ShelfCdPlayer.I.addListener(_syncPlayerState);
    if (ShelfCdPlayer.I.isCdPlaying(widget.cd.id)) {
      _spinCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ShelfCdWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPlayerState();
  }

  void _syncPlayerState() {
    if (!mounted) return;
    final isPlaying = ShelfCdPlayer.I.isCdPlaying(widget.cd.id);
    if (isPlaying && !_spinCtrl.isAnimating) {
      _spinCtrl.repeat();
      setState(() {});
    } else if (!isPlaying && _spinCtrl.isAnimating) {
      _spinCtrl.stop();
      setState(() {});
    }
  }

  @override
  void dispose() {
    ShelfCdPlayer.I.removeListener(_syncPlayerState);
    _spinCtrl.dispose();
    super.dispose();
  }

  void _tearCd() {
    if (_isTorn) return;
    setState(() => _isTorn = true);
    Sfx.play('tear');
    Buzz.medium();
    Future.delayed(const Duration(milliseconds: 380), () {
      if (mounted) widget.onTear?.call();
    });
  }

  void _onTap() {
    Buzz.tick();
    if (widget.home) {
      // Home screen behavior: Play or Pause song
      if (widget.cd.audioFile == null || widget.cd.audioFile!.isEmpty) {
        toast('No song uploaded yet · Open this shelf in Library to add an MP3 song 💿');
        return;
      }
      final isPlaying = ShelfCdPlayer.I.isCdPlaying(widget.cd.id);
      ShelfCdPlayer.I.togglePlay(widget.cd);
      if (!isPlaying) {
        Sfx.play('fanfare');
        toast('Playing: ${widget.cd.title ?? "CD Song"} 🎵');
      } else {
        toast('Paused ⏸️');
      }
    } else {
      // Library screen behavior: Manage CD / Upload MP3
      _openLibraryCdDialog();
    }
  }

  Future<void> _pickAndUploadSong(BuildContext ctx, StateSetter set) async {
    final PlatformFile? f;
    try {
      f = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
        dialogTitle: 'Select an MP3 song for your CD',
      );
    } catch (_) {
      toast('Could not open file picker');
      return;
    }

    if (f == null) return;

    toast('Uploading ${f.name}… 🎵');
    try {
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : 'mp3';
      final fileName = 'cd_${newId()}.$ext';
      final dest = store.audioFile(fileName);

      final src = f.path;
      if (src != null && File(src).existsSync()) {
        await File(src).copy(dest.path);
      } else {
        await dest.writeAsBytes(await f.readAsBytes(), flush: true);
      }

      final songTitle = f.name
          .replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|ogg)$', caseSensitive: false), '')
          .replaceAll(RegExp(r'[_\-]+'), ' ')
          .trim();

      // Clean up previous audio file if replaced
      if (widget.cd.audioFile != null && widget.cd.audioFile != fileName) {
        store.deleteAudio(widget.cd.audioFile);
      }

      setState(() {
        widget.cd.audioFile = fileName;
        widget.cd.title = songTitle.isEmpty ? 'Shelfwise Music Track' : songTitle;
      });
      set(() {});
      store.changed();
      Sfx.play('fanfare');
      toast('Song uploaded to CD! 💿 Tap it on Home to play');
    } catch (e) {
      debugPrint('Shelfwise: CD song upload failed: $e');
      toast('Could not save MP3 file');
    }
  }

  void _openLibraryCdDialog() {
    Buzz.tick();
    openDialog((ctx) => StatefulBuilder(
          builder: (ctx, set) {
            final hasSong = widget.cd.audioFile != null && widget.cd.audioFile!.isNotEmpty;
            final isPlaying = ShelfCdPlayer.I.isCdPlaying(widget.cd.id);

            return AppDialog(
              title: 'Shelf CD Player 💿',
              maxWidth: 340,
              actions: [
                const Btn('Close'),
                Btn('Remove CD 🗑️', kind: Kind.dng, onTap: () {
                  _tearCd();
                  return true;
                }),
              ],
              children: [
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x33000000),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: _CdDiscGraphic(
                      rotationAngle: 0.0,
                      isPlaying: isPlaying,
                      title: widget.cd.title,
                      size: 80,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (hasSong) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: C.field,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: C.inputLine),
                    ),
                    child: Row(
                      children: [
                        const Text('🎵', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.cd.title ?? 'Audio Track',
                                style: nu(13.5, FontWeight.w800),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Ready to play on Home shelf',
                                style: nu(11, FontWeight.w600, C.muted),
                              ),
                            ],
                          ),
                        ),
                        Pressable(
                          onTap: () {
                            ShelfCdPlayer.I.togglePlay(widget.cd);
                            set(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isPlaying ? C.brown : const Color(0xFF2E7D32),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Pressable(
                    onTap: () => _pickAndUploadSong(ctx, set),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: C.chip,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x22000000)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Change / Replace Song 📂',
                        style: nu(12.5, FontWeight.w800, C.chipText),
                      ),
                    ),
                  ),
                ] else ...[
                  Text(
                    'This CD has no song yet. Upload an MP3 song to play when you tap it from your Home shelf!',
                    style: nu(12.5, FontWeight.w600, C.muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Pressable(
                    onTap: () => _pickAndUploadSong(ctx, set),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: C.brown,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33B8692A),
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          )
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.upload_file, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Upload MP3 Song 🎵',
                            style: nu(13.5, FontWeight.w800, Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Only 1 CD with 1 song is allowed per shelf. Removing or tearing this CD permanently deletes the song.',
                  style: nu(11, FontWeight.w600, C.muted),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        ));
  }

  @override
  Widget build(BuildContext context) {
    const discSize = 62.0;

    if (_isTorn) {
      return SizedBox(
        width: discSize,
        height: discSize,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeIn,
          builder: (_, t, _) {
            return Opacity(
              opacity: (1.0 - t).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 1.0 - (t * 0.4),
                child: Transform.rotate(
                  angle: t * 0.5,
                  child: _CdDiscGraphic(
                    rotationAngle: 0.0,
                    isPlaying: false,
                    title: widget.cd.title,
                    size: discSize,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    final isPlaying = ShelfCdPlayer.I.isCdPlaying(widget.cd.id);

    return GestureDetector(
      onTap: _onTap,
      onDoubleTap: _tearCd,
      onPanStart: (_) {
        setState(() {
          _isDragging = true;
          _dragVx = 0.0;
        });
        Buzz.light();
      },
      onPanUpdate: (details) {
        setState(() {
          _dragVx = (_dragVx * 0.6 + (details.delta.dx * 0.4)).clamp(-15.0, 15.0);
        });
        widget.onMoved?.call(details.delta.dx, details.delta.dy);
      },
      onPanEnd: (_) {
        setState(() {
          _isDragging = false;
          _dragVx = 0.0;
        });
      },
      child: AnimatedBuilder(
        animation: _spinCtrl,
        builder: (context, _) {
          // If playing: continuous full 360 degree spin!
          // If not playing: natural slight tilt on the shelf
          final currentAngle = isPlaying
              ? (_spinCtrl.value * 2 * pi)
              : ((widget.cd.r + _dragVx * 0.7) * pi / 180);

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Subtle shelf shadow
              Positioned(
                bottom: -2,
                child: Container(
                  width: discSize * 0.7,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(0, 0, 0, _isDragging ? 0.35 : 0.22),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, _isDragging ? 0.30 : 0.18),
                        blurRadius: _isDragging ? 12 : 5,
                        offset: Offset(0, _isDragging ? 8 : 3),
                      )
                    ],
                  ),
                ),
              ),

              // Animated floating music notes when playing!
              if (isPlaying) ...[
                _FloatingNote(val: _spinCtrl.value, dx: -14, dy: -36, note: '♪'),
                _FloatingNote(val: (_spinCtrl.value + 0.33) % 1.0, dx: 18, dy: -42, note: '♫'),
                _FloatingNote(val: (_spinCtrl.value + 0.66) % 1.0, dx: 0, dy: -50, note: '♬'),
              ],

              // Glowing aura when playing
              if (isPlaying)
                Container(
                  width: discSize + 8,
                  height: discSize + 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x66FFC107),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),

              // The Compact Disc Graphic
              _CdDiscGraphic(
                rotationAngle: currentAngle,
                isPlaying: isPlaying,
                title: widget.cd.title,
                size: discSize,
              ),

              // Small play indicator badge when stopped on Home
              if (widget.home && !isPlaying && widget.cd.audioFile != null && widget.cd.audioFile!.isNotEmpty)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2E7D32),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x44000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        )
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 11,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Floating note micro-animation drifting up while playing
class _FloatingNote extends StatelessWidget {
  final double val;
  final double dx;
  final double dy;
  final String note;

  const _FloatingNote({
    required this.val,
    required this.dx,
    required this.dy,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final yOffset = dy - (val * 16.0);
    final opacity = sin(val * pi).clamp(0.0, 1.0);

    return Positioned(
      left: 31 + dx + sin(val * 4 * pi) * 4,
      top: yOffset,
      child: Opacity(
        opacity: opacity,
        child: Text(
          note,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: const Color(0xFFB8692A),
            shadows: const [
              Shadow(color: Colors.white, blurRadius: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Realistic CD disc graphic with holographic rainbow sweep reflection,
/// concentric laser grooves, and inner spindle hub.
class _CdDiscGraphic extends StatelessWidget {
  final double rotationAngle;
  final bool isPlaying;
  final String? title;
  final double size;

  const _CdDiscGraphic({
    required this.rotationAngle,
    required this.isPlaying,
    required this.title,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotationAngle,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            center: Alignment.center,
            colors: [
              Color(0xFFE8EEF5),
              Color(0xFFC7D7E8),
              Color(0xFFFFD5E5),
              Color(0xFFD6F5E3),
              Color(0xFFFFF2C2),
              Color(0xFFD1E4FA),
              Color(0xFFE8EEF5),
            ],
            stops: [0.0, 0.2, 0.4, 0.6, 0.78, 0.9, 1.0],
          ),
          border: Border.all(
            color: const Color(0x66FFFFFF),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x28000000),
              offset: Offset(0, 3),
              blurRadius: 6,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Concentric laser track grooves
            Container(
              width: size * 0.86,
              height: size * 0.86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x1A000000), width: 0.8),
              ),
            ),
            Container(
              width: size * 0.72,
              height: size * 0.72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x18000000), width: 0.7),
              ),
            ),

            // Holographic specular gloss reflection
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.3),
                  radius: 0.85,
                  colors: [
                    Colors.white.withValues(alpha: 0.48),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),

            // Centre Label Disc (Dark vinyl / retro album center)
            Container(
              width: size * 0.46,
              height: size * 0.46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF263238),
                border: Border.all(color: const Color(0x55FFFFFF), width: 1.0),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(2),
              child: Text(
                title?.isNotEmpty == true
                    ? (title!.length > 7 ? '${title!.substring(0, 7)}…' : title!)
                    : '💿',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFFD54F),
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Inner clear plastic ring
            Container(
              width: size * 0.22,
              height: size * 0.22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.35),
                border: Border.all(color: const Color(0x44000000), width: 0.6),
              ),
            ),

            // Center spindle hole (hollow through to shelf)
            Container(
              width: size * 0.12,
              height: size * 0.12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xAA1C1814),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 1.5,
                    spreadRadius: -0.5,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
