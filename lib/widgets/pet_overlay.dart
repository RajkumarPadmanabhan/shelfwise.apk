import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/sfx.dart';

/// Represents a physical shelf on the Home screen that a pet can jump onto,
/// walk across, sit on, and jump upwards from.
class ShelfSurface {
  final String id;
  final Rect rect;
  final double surfaceY;
  final double minX;
  final double maxX;

  ShelfSurface({
    required this.id,
    required this.rect,
    required this.surfaceY,
    required this.minX,
    required this.maxX,
  });
}

class ShelfBoundsRegistry {
  static final Map<String, GlobalKey> _shelfKeys = {};
  static final Map<String, Rect> homeShelves = {};

  static void register(String key, GlobalKey gk) {
    _shelfKeys[key] = gk;
  }

  static void unregister(String key) {
    _shelfKeys.remove(key);
    homeShelves.remove(key);
  }

  /// Returns all currently mounted and on-screen shelves on the Home page,
  /// sorted from bottom to top (descending surfaceY: index 0 is lowest shelf,
  /// index last is highest shelf).
  static List<ShelfSurface> getLiveShelves({
    required double topLimit,
    required double bottomLimit,
  }) {
    final list = <ShelfSurface>[];
    for (final entry in _shelfKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final ro = ctx.findRenderObject() as RenderBox?;
      if (ro == null || !ro.hasSize || !ro.attached) continue;
      final pos = ro.localToGlobal(Offset.zero);
      final rect = Rect.fromLTWH(pos.dx, pos.dy, ro.size.width, ro.size.height);
      homeShelves[entry.key] = rect;

      // Surface line is where books stand and pet sits/walks (near bottom of shelf box)
      final surfaceY = pos.dy + ro.size.height - 14.0;
      if (surfaceY > topLimit && surfaceY < bottomLimit) {
        list.add(ShelfSurface(
          id: entry.key,
          rect: rect,
          surfaceY: surfaceY,
          minX: (pos.dx + 26.0).clamp(24.0, 150.0),
          maxX: (pos.dx + ro.size.width - 26.0).clamp(160.0, 1200.0),
        ));
      }
    }
    // Sort descending by surfaceY: index 0 is closest to the floor, index last is highest up
    list.sort((a, b) => b.surfaceY.compareTo(a.surfaceY));
    return list;
  }
}

class TodoBoundsRegistry {
  static final Map<String, Rect> items = {};
}

/// Overlay that renders the chosen companion pet across all screens.
/// Features:
/// - Roams floor across all tabs.
/// - On Home page (tab == 0): Jumps up onto shelves, perches, naps, hops between shelves.
/// - On Library page (tab == 1): Does NOT jump onto shelves (per user instruction).
/// - On To-do page (tab == 2): Jumps onto to-do list items, performs naughty antics, jumps between them.
/// - Double-tap: Pet gets scared, plays panic sound, runs rapidly off-screen.
/// - Single-tap: Greets with species sound and happy hop.
class PetOverlay extends StatefulWidget {
  final int tab;
  const PetOverlay({super.key, required this.tab});

  @override
  State<PetOverlay> createState() => _PetOverlayState();
}

class _PetOverlayState extends State<PetOverlay> with TickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat();

  double _x = 100;
  double _y = 500;
  double _facing = 1; // 1 facing right, -1 facing left
  String _state = 'walk'; // walk, run, sit, lick, sleep, jump, naughty
  bool _fleeing = false;
  bool _offScreen = false;
  String? _naughtyEmoji;
  int _loopId = 0;
  Timer? _fleeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPosition();
      _startLifeLoop();
    });
  }

  @override
  void didUpdateWidget(PetOverlay old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) {
      _loopId++;
      _fleeTimer?.cancel();
      _fleeing = false;
      _offScreen = false;
      if (widget.tab == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.tab == 0) {
            _initPosition();
            _startLifeLoop();
          }
        });
      } else {
        setState(() {
          _naughtyEmoji = null;
          _state = 'sit';
        });
      }
    }
  }

  @override
  void dispose() {
    _fleeTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  double _floorY(Size size, EdgeInsets padding) {
    // Floor is just above the bottom frosted navigation bar (~72px + bottom inset)
    return size.height - padding.bottom - 78;
  }

  void _initPosition() {
    if (!mounted) return;
    final mq = MediaQuery.of(context);
    final floor = _floorY(mq.size, mq.padding);
    setState(() {
      _x = (mq.size.width * .3).clamp(40.0, mq.size.width - 80.0);
      _y = floor;
      _facing = 1;
      _state = 'sit';
    });
  }

  Future<void> _flee() async {
    if (_fleeing || store.settings.pet == 'none' || widget.tab != 0) return;
    final kind = store.settings.pet;
    _fleeing = true;
    _loopId++;
    final curLoop = _loopId;

    Sfx.pet(kind, 'scare');

    final size = MediaQuery.sizeOf(context);
    final targetX = _x < size.width / 2 ? -90.0 : size.width + 90.0;
    final dir = targetX > _x ? 1.0 : -1.0;

    setState(() {
      _facing = dir;
      _state = 'run';
      _naughtyEmoji = '💨';
    });

    // Run off-screen rapidly
    final startX = _x;
    final dist = (targetX - startX).abs();
    final durationMs = (dist * 2.8).clamp(400.0, 950.0).toInt();
    final t0 = DateTime.now();

    while (mounted && curLoop == _loopId) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      final t = (elapsed / durationMs).clamp(0.0, 1.0);
      setState(() {
        _x = startX + (targetX - startX) * t;
      });
      if (t >= 1.0) break;
      await Future.delayed(const Duration(milliseconds: 16));
    }

    if (!mounted || curLoop != _loopId) return;
    setState(() {
      _offScreen = true;
      _naughtyEmoji = null;
    });

    // Return after ~12 seconds
    _fleeTimer?.cancel();
    _fleeTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      setState(() {
        _fleeing = false;
        _offScreen = false;
        _initPosition();
        _startLifeLoop();
      });
    });
  }

  void _tapPet() {
    if (_fleeing || store.settings.pet == 'none' || widget.tab != 0) return;
    final kind = store.settings.pet;
    Sfx.pet(kind, 'call');
    setState(() {
      _state = 'jump';
      _naughtyEmoji = '❤️';
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && !_fleeing) {
        setState(() {
          _state = 'sit';
          _naughtyEmoji = null;
        });
      }
    });
  }

  Future<void> _walkTo(double targetX, {double speed = 65, required int loop}) async {
    final startX = _x;
    final dist = targetX - startX;
    if (dist.abs() < 4) return;
    setState(() {
      _facing = dist > 0 ? 1 : -1;
      _state = 'walk';
    });
    final durationMs = (dist.abs() / speed * 1000).clamp(300.0, 4000.0).toInt();
    final t0 = DateTime.now();
    while (mounted && loop == _loopId && !_fleeing) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      final t = (elapsed / durationMs).clamp(0.0, 1.0);
      setState(() {
        _x = startX + dist * t;
      });
      if (t >= 1.0) break;
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _flyTo(
    double tx,
    double ty, {
    required int loop,
    double speed = 135,
    double swoop = 22,
  }) async {
    final startX = _x;
    final startY = _y;
    final dx = tx - startX;
    final dy = ty - startY;
    if (dx.abs() < 4 && dy.abs() < 4) return;
    setState(() {
      _facing = dx >= 0 ? 1 : -1;
      _state = 'fly';
    });
    final dist = sqrt(dx * dx + dy * dy);
    final durationMs = (dist / speed * 1000).clamp(450.0, 3200.0).toInt();
    final t0 = DateTime.now();
    while (mounted && loop == _loopId && !_fleeing) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      final t = (elapsed / durationMs).clamp(0.0, 1.0);
      final wave = sin(t * pi) * swoop;
      setState(() {
        _x = startX + dx * t;
        _y = startY + dy * t - wave;
      });
      if (t >= 1.0) break;
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _jumpTo(double tx, double ty, {required int loop, double rise = 38}) async {
    final startX = _x;
    final startY = _y;
    final dx = tx - startX;
    final dy = ty - startY;
    setState(() {
      _facing = dx >= 0 ? 1 : -1;
      _state = 'jump';
    });
    final durationMs = (max(dx.abs(), dy.abs()) * 1.8).clamp(420.0, 850.0).toInt();
    final t0 = DateTime.now();
    while (mounted && loop == _loopId && !_fleeing) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      final t = (elapsed / durationMs).clamp(0.0, 1.0);
      final parabolic = 4 * rise * t * (1 - t);
      setState(() {
        _x = startX + dx * t;
        _y = startY + dy * t - parabolic;
      });
      if (t >= 1.0) break;
      await Future.delayed(const Duration(milliseconds: 16));
    }
    if (mounted && loop == _loopId && !_fleeing) {
      setState(() {
        _x = tx;
        _y = ty;
        _state = 'sit';
      });
      Sfx.pet(store.settings.pet, 'land');
    }
  }

  Future<void> _doBirdHomeFlightRoutine(
    Size size,
    EdgeInsets padding,
    double floor,
    List<ShelfSurface> shelves,
    int curLoop,
    Random rnd,
  ) async {
    // 1. Chirp and take off upwards into the sky!
    Sfx.pet('bird', 'call');
    final takeOffY = (floor * 0.40 + rnd.nextDouble() * 60.0).clamp(padding.top + 75.0, floor - 100.0);
    final takeOffX = (_x + (rnd.nextBool() ? 80.0 : -80.0)).clamp(40.0, size.width - 60.0);
    await _flyTo(takeOffX, takeOffY, loop: curLoop, speed: 130, swoop: 26);
    if (curLoop != _loopId || _fleeing || widget.tab != 0) return;

    // 2. Swoop through the air
    final destX = (_x < size.width * 0.5)
        ? size.width * (0.65 + rnd.nextDouble() * 0.25)
        : size.width * (0.10 + rnd.nextDouble() * 0.25);
    final destY = (padding.top + 70.0 + rnd.nextDouble() * (floor - padding.top - 180.0))
        .clamp(padding.top + 70.0, floor - 100.0);
    await _flyTo(destX.clamp(40.0, size.width - 60.0), destY, loop: curLoop, speed: 140, swoop: 24);
    if (curLoop != _loopId || _fleeing || widget.tab != 0) return;

    // 3. Land on one of the shelves or floor
    double landX = _x;
    double landY = floor;
    ShelfSurface? chosenShelf;

    if (shelves.isNotEmpty && rnd.nextDouble() < 0.75) {
      chosenShelf = shelves[rnd.nextInt(shelves.length)];
      landX = _x.clamp(chosenShelf.minX, chosenShelf.maxX);
      landY = chosenShelf.surfaceY;
    } else {
      landX = _x.clamp(40.0, size.width - 60.0);
      landY = floor;
    }

    await _flyTo(landX, landY, loop: curLoop, speed: 115, swoop: 14);
    if (curLoop != _loopId || _fleeing || widget.tab != 0) return;

    setState(() {
      _x = landX;
      _y = landY;
      _state = 'sit';
    });
    Sfx.pet('bird', 'land');

    // If on a shelf: walk through the shelf, sing notes!
    if (chosenShelf != null) {
      final walkTarget = (_x + (rnd.nextBool() ? 1 : -1) * (30.0 + rnd.nextDouble() * 50.0))
          .clamp(chosenShelf.minX, chosenShelf.maxX);
      await _walkTo(walkTarget, speed: 60, loop: curLoop);
      if (curLoop != _loopId || _fleeing || widget.tab != 0) return;
    }

    // Sing notes
    setState(() => _naughtyEmoji = '🎵');
    Sfx.pet('bird', 'call');
    await Future.delayed(Duration(milliseconds: 1800 + rnd.nextInt(1200)));
    if (curLoop != _loopId || _fleeing || widget.tab != 0) return;
    setState(() => _naughtyEmoji = null);
  }

  Future<void> _startLifeLoop() async {
    final curLoop = ++_loopId;
    final rnd = Random();

    while (mounted && curLoop == _loopId && !_fleeing && !_offScreen) {
      if (widget.tab != 0) return;
      if (store.settings.pet == 'none') {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      final padding = MediaQuery.paddingOf(context);
      final floor = _floorY(size, padding);
      final kind = store.settings.pet;

      // Query live on-screen shelf platforms on Home (sorted bottom-to-top)
      final shelves = ShelfBoundsRegistry.getLiveShelves(
        topLimit: padding.top + 70,
        bottomLimit: floor - 10,
      );

      // --- Bird Routine (Home only) ---
      if (kind == 'bird' && rnd.nextDouble() < 0.50) {
        await _doBirdHomeFlightRoutine(size, padding, floor, shelves, curLoop, rnd);
        continue;
      }

      // --- Four-legged pets (Cat, Dog, Rabbit) on Home Shelves & Floor ---
      final onFloor = (_y - floor).abs() < 14;

      // Detect which shelf pet is currently standing on (if any)
      ShelfSurface? curShelf;
      for (final s in shelves) {
        if ((_y - s.surfaceY).abs() < 16) {
          curShelf = s;
          break;
        }
      }

      if (onFloor || curShelf == null) {
        // Pet is currently on the floor!
        if ((_y - floor).abs() > 2) {
          setState(() => _y = floor);
        }

        // Decide whether to explore shelves or roam floor
        if (shelves.isNotEmpty && rnd.nextDouble() < 0.75) {
          // Pet jumps into the shelves! Start with lowest shelf (shelves[0])
          final targetShelf = shelves[0];
          final targetX = _x.clamp(targetShelf.minX, targetShelf.maxX);

          // 1. Walk underneath the shelf first
          await _walkTo(targetX, loop: curLoop);
          if (curLoop != _loopId || _fleeing || widget.tab != 0) return;

          // 2. Jump UPWARDS onto the shelf!
          await _jumpTo(targetX, targetShelf.surfaceY, loop: curLoop, rise: 48);
          if (curLoop != _loopId || _fleeing || widget.tab != 0) return;

          // Land and sit
          setState(() => _state = 'sit');
          await Future.delayed(Duration(milliseconds: 1000 + rnd.nextInt(1000)));
          if (curLoop != _loopId || _fleeing || widget.tab != 0) return;
        } else {
          // Roam the floor for a bit
          final deltaX = (rnd.nextBool() ? 1 : -1) * (45.0 + rnd.nextDouble() * 80.0);
          final targetFloorX = (_x + deltaX).clamp(40.0, size.width - 60.0);
          await _walkTo(targetFloorX, loop: curLoop);
          if (curLoop != _loopId || _fleeing || widget.tab != 0) return;

          setState(() => _state = 'sit');
          if (rnd.nextDouble() < 0.35) Sfx.pet(kind, 'call');
          await Future.delayed(Duration(milliseconds: 1400 + rnd.nextInt(1400)));
          if (curLoop != _loopId || _fleeing || widget.tab != 0) return;

          if (rnd.nextDouble() < 0.45) {
            setState(() => _state = 'lick');
            await Future.delayed(Duration(milliseconds: 1800 + rnd.nextInt(1400)));
            if (curLoop != _loopId || _fleeing || widget.tab != 0) return;
          }
          continue;
        }
      }

      // --- When on a Shelf: Walk through the shelf, sit, groom, nap, and jump upwards! ---
      final curIndex = curShelf != null ? shelves.indexOf(curShelf) : 0;
      final activeShelf = curIndex >= 0 && curIndex < shelves.length ? shelves[curIndex] : shelves[0];

      // Keep Y snapped to current shelf surface in case of scrolling
      if ((_y - activeShelf.surfaceY).abs() > 3) {
        setState(() => _y = activeShelf.surfaceY);
      }

      // 1. Walk through the shelf!
      final walkRange = (activeShelf.maxX - activeShelf.minX);
      if (walkRange > 30) {
        final walkOffset = (rnd.nextBool() ? 1 : -1) * (40.0 + rnd.nextDouble() * 80.0);
        final walkTargetX = (_x + walkOffset).clamp(activeShelf.minX, activeShelf.maxX);
        await _walkTo(walkTargetX, speed: 55, loop: curLoop);
        if (curLoop != _loopId || _fleeing || widget.tab != 0) return;
      }

      // 2. Sit on the shelf
      setState(() => _state = 'sit');
      if (rnd.nextDouble() < 0.35) Sfx.pet(kind, 'call');
      await Future.delayed(Duration(milliseconds: 1200 + rnd.nextInt(1200)));
      if (curLoop != _loopId || _fleeing || widget.tab != 0) return;

      // 3. Groom / Lick paws
      if (rnd.nextDouble() < 0.5) {
        setState(() => _state = 'lick');
        await Future.delayed(Duration(milliseconds: 1600 + rnd.nextInt(1400)));
        if (curLoop != _loopId || _fleeing || widget.tab != 0) return;
      }

      // 4. Sometimes nap on the shelf between the books
      if (rnd.nextDouble() < 0.35) {
        setState(() {
          _state = 'sleep';
          _naughtyEmoji = '💤';
        });
        Sfx.pet(kind, 'sleep');
        await Future.delayed(Duration(milliseconds: 3200 + rnd.nextInt(2800)));
        if (curLoop != _loopId || _fleeing || widget.tab != 0) return;
        setState(() {
          _state = 'sit';
          _naughtyEmoji = null;
        });
      }

      // 5. Sometimes walk again along the shelf to another spot
      if (rnd.nextDouble() < 0.5 && walkRange > 40) {
        final secondWalkX = (activeShelf.minX + rnd.nextDouble() * walkRange).clamp(activeShelf.minX, activeShelf.maxX);
        await _walkTo(secondWalkX, speed: 50, loop: curLoop);
        if (curLoop != _loopId || _fleeing || widget.tab != 0) return;
        setState(() => _state = 'sit');
        await Future.delayed(const Duration(milliseconds: 800));
        if (curLoop != _loopId || _fleeing || widget.tab != 0) return;
      }

      // 6. Jump Decision: "jump into upwards of each shelf"
      // Since shelves is sorted bottom-to-top, curIndex + 1 is the shelf ABOVE!
      final hasShelfAbove = curIndex + 1 < shelves.length;
      final shouldJumpUp = hasShelfAbove && rnd.nextDouble() < 0.70;

      if (shouldJumpUp) {
        // Jump UPWARDS to the shelf above!
        final nextShelfAbove = shelves[curIndex + 1];
        final jumpX = _x.clamp(nextShelfAbove.minX, nextShelfAbove.maxX);
        await _jumpTo(jumpX, nextShelfAbove.surfaceY, loop: curLoop, rise: 48);
        if (curLoop != _loopId || _fleeing || widget.tab != 0) return;
        continue;
      } else {
        // If no shelf above, or after reaching higher shelves, decide to jump down
        if (curIndex > 0 && rnd.nextDouble() < 0.45) {
          // Jump down to the shelf below!
          final nextShelfBelow = shelves[curIndex - 1];
          final jumpX = _x.clamp(nextShelfBelow.minX, nextShelfBelow.maxX);
          await _jumpTo(jumpX, nextShelfBelow.surfaceY, loop: curLoop, rise: 22);
          if (curLoop != _loopId || _fleeing || widget.tab != 0) return;
          continue;
        } else {
          // Jump down to the floor
          final jumpFloorX = _x.clamp(40.0, size.width - 60.0);
          await _jumpTo(jumpFloorX, floor, loop: curLoop, rise: 24);
          if (curLoop != _loopId || _fleeing || widget.tab != 0) return;
          setState(() => _state = 'sit');
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final kind = store.settings.pet;
        if (widget.tab != 0 || kind == 'none' || _offScreen) return const SizedBox.shrink();

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _x - 35,
              top: _y - 56,
              width: 70,
              height: 64,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _flee,
                onTap: _tapPet,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (_naughtyEmoji != null)
                      Positioned(
                        top: -16,
                        left: 24,
                        child: AnimatedBuilder(
                          animation: _anim,
                          builder: (_, _) => Transform.translate(
                            offset: Offset(0, sin(_anim.value * 2 * pi) * 3),
                            child: Text(_naughtyEmoji!, style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                      ),
                    AnimatedBuilder(
                      animation: _anim,
                      builder: (_, _) => Transform.scale(
                        scaleX: _facing,
                        alignment: Alignment.bottomCenter,
                        child: CustomPaint(
                          size: const Size(70, 56),
                          painter: _PetPainter(
                            kind: kind,
                            state: _state,
                            animValue: _anim.value,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Custom painter rendering Cat, Dog, Rabbit, and Bird matching the SVG artwork.
class _PetPainter extends CustomPainter {
  final String kind;
  final String state;
  final double animValue;

  _PetPainter({required this.kind, required this.state, required this.animValue});

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case 'cat':
        _paintCat(canvas, size);
        break;
      case 'dog':
        _paintDog(canvas, size);
        break;
      case 'rabbit':
        _paintRabbit(canvas, size);
        break;
      case 'bird':
        _paintBird(canvas, size);
        break;
    }
  }

  static void _drawArticulatedLeg(
    Canvas canvas, {
    required Offset joint,
    required double angle,
    required Color color,
    required double length,
    required double width,
    required bool isHind,
    required String state,
    bool isSitting = false,
    bool isSleeping = false,
  }) {
    canvas.save();
    canvas.translate(joint.dx, joint.dy);

    if (isSleeping) {
      // Paws tucked under resting body loaf
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-3, 6, 9, 4), const Radius.circular(2)),
        Paint()..color = color,
      );
      canvas.restore();
      return;
    }

    if (isSitting) {
      if (isHind) {
        // Sitting hind leg: folded crouch flank and flat resting foot
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(1, 4), width: 14, height: 11),
          Paint()..color = color,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(0, 8, 10, 4), const Radius.circular(2)),
          Paint()..color = color,
        );
        canvas.restore();
        return;
      } else {
        // Sitting front leg: straight upright supporting body
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(-width / 2, 0, width, length), const Radius.circular(2.5)),
          Paint()..color = color,
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(0, length), width: width + 2, height: 3.5),
          Paint()..color = color,
        );
        canvas.restore();
        return;
      }
    }

    // Walking / Running / Jumping:
    canvas.rotate(angle);

    final swingForward = angle > 0;
    final kneeBend = swingForward ? (sin(angle.abs()) * 2.5) : 0.0;

    final path = Path();
    if (isHind) {
      path.moveTo(-width * 0.6, 0);
      path.lineTo(width * 0.6, 0);
      path.lineTo(width * 0.45, length * 0.55);
      path.lineTo(width * 0.4 + kneeBend, length - 1);
      path.lineTo(-width * 0.4 + kneeBend, length - 1);
      path.lineTo(-width * 0.45, length * 0.55);
      path.close();
    } else {
      path.moveTo(-width * 0.5, 0);
      path.lineTo(width * 0.5, 0);
      path.lineTo(width * 0.4 + kneeBend, length - 1);
      path.lineTo(-width * 0.4 + kneeBend, length - 1);
      path.close();
    }
    canvas.drawPath(path, Paint()..color = color);

    // Rounded paw pad
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(kneeBend + 0.8, length),
        width: width + 2.5,
        height: 4,
      ),
      Paint()..color = color,
    );

    canvas.restore();
  }

  void _paintCat(Canvas canvas, Size size) {
    const bodyCol = Color(0xFFE9A45E);
    const bellyCol = Color(0xFFF6D9B0);
    const darkCol = Color(0xFFC47F3C);
    const earCol = Color(0xFFF4A6A6);

    final isMoving = state == 'walk' || state == 'run';
    final isSitting = state == 'sit';
    final isSleeping = state == 'sleep';

    final cycle = animValue * 2 * pi;
    final maxAngle = (state == 'run') ? 0.72 : 0.42;
    final bob = isMoving ? (sin(animValue * 4 * pi).abs() * (state == 'run' ? 2.8 : 1.8)) : 0.0;

    // Diagonal trot gait (hind-far & front-near move together, hind-near & front-far opposite)
    final hindFarAngle = isMoving ? sin(cycle) * maxAngle : (state == 'jump' ? -0.5 : 0.0);
    final frontNearAngle = isMoving ? sin(cycle) * maxAngle : (state == 'jump' ? 0.45 : 0.0);
    final hindNearAngle = isMoving ? -sin(cycle) * maxAngle : (state == 'jump' ? -0.45 : 0.0);
    final frontFarAngle = isMoving ? -sin(cycle) * maxAngle : (state == 'jump' ? 0.5 : 0.0);

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(36, 54), width: isSleeping ? 38 : 44, height: 6),
      Paint()..color = const Color(0x28000000),
    );

    // 1. Far legs (drawn behind body in darker shade)
    _drawArticulatedLeg(
      canvas,
      joint: Offset(22, 38 - bob),
      angle: hindFarAngle,
      color: darkCol,
      length: 15,
      width: 5.5,
      isHind: true,
      state: state,
      isSitting: isSitting,
      isSleeping: isSleeping,
    );
    _drawArticulatedLeg(
      canvas,
      joint: Offset(46, 38 - bob),
      angle: frontFarAngle,
      color: darkCol,
      length: 15,
      width: 5.5,
      isHind: false,
      state: state,
      isSitting: isSitting,
      isSleeping: isSleeping,
    );

    // 2. Tail
    final tailPaint = Paint()
      ..color = bodyCol
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final tailWag = sin(animValue * 2 * pi) * (state == 'run' ? 12.0 : 7.0);
    final tailPath = Path();
    if (isSleeping) {
      tailPath
        ..moveTo(16, 42)
        ..cubicTo(12, 46, 26, 48, 34, 46);
    } else {
      tailPath
        ..moveTo(16, 42 - bob)
        ..cubicTo(8, 38 - bob, 4 + tailWag, 22 - bob, 12 + tailWag, 18 - bob);
    }
    canvas.drawPath(tailPath, tailPaint);

    // 3. Body & Belly
    canvas.drawOval(
      Rect.fromCenter(center: Offset(35, 40 - bob), width: 38, height: 22),
      Paint()..color = bodyCol,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(37, 44 - bob), width: 26, height: 11),
      Paint()..color = bellyCol,
    );

    // 4. Near legs (drawn in front of body in primary body shade)
    _drawArticulatedLeg(
      canvas,
      joint: Offset(22, 38 - bob),
      angle: hindNearAngle,
      color: bodyCol,
      length: 15,
      width: 5.5,
      isHind: true,
      state: state,
      isSitting: isSitting,
      isSleeping: isSleeping,
    );
    _drawArticulatedLeg(
      canvas,
      joint: Offset(46, 38 - bob),
      angle: frontNearAngle,
      color: bodyCol,
      length: 15,
      width: 5.5,
      isHind: false,
      state: state,
      isSitting: isSitting,
      isSleeping: isSleeping,
    );

    // 5. Head
    final headCenter = Offset(52, 28 - bob);
    canvas.drawCircle(headCenter, 11, Paint()..color = bodyCol);

    // Ears
    final leftEar = Path()
      ..moveTo(headCenter.dx - 9, headCenter.dy - 6)
      ..lineTo(headCenter.dx - 8, headCenter.dy - 19)
      ..lineTo(headCenter.dx - 1, headCenter.dy - 9)
      ..close();
    canvas.drawPath(leftEar, Paint()..color = bodyCol);
    canvas.drawPath(leftEar, Paint()..color = earCol..style = PaintingStyle.stroke..strokeWidth = 2);

    final rightEar = Path()
      ..moveTo(headCenter.dx + 1, headCenter.dy - 9)
      ..lineTo(headCenter.dx + 8, headCenter.dy - 19)
      ..lineTo(headCenter.dx + 10, headCenter.dy - 5)
      ..close();
    canvas.drawPath(rightEar, Paint()..color = bodyCol);
    canvas.drawPath(rightEar, Paint()..color = earCol..style = PaintingStyle.stroke..strokeWidth = 2);

    // Snout
    canvas.drawOval(
      Rect.fromCenter(center: Offset(headCenter.dx + 7, headCenter.dy + 4), width: 10, height: 8),
      Paint()..color = bellyCol,
    );
    canvas.drawCircle(Offset(headCenter.dx + 10, headCenter.dy + 2.5), 1.8, Paint()..color = const Color(0xFFE8788A));

    // Whiskers
    final whiskerPaint = Paint()
      ..color = const Color(0xFF8A6A4A)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(headCenter.dx + 9, headCenter.dy + 4), Offset(headCenter.dx + 18, headCenter.dy + 2), whiskerPaint);
    canvas.drawLine(Offset(headCenter.dx + 9, headCenter.dy + 5.5), Offset(headCenter.dx + 18, headCenter.dy + 7.5), whiskerPaint);

    // Eye
    if (isSleeping) {
      final sleepEye = Path()
        ..moveTo(headCenter.dx + 2, headCenter.dy - 2)
        ..quadraticBezierTo(headCenter.dx + 5, headCenter.dy + 1, headCenter.dx + 8, headCenter.dy - 2);
      canvas.drawPath(sleepEye, Paint()..color = const Color(0xFF2B2B2B)..style = PaintingStyle.stroke..strokeWidth = 1.4);
    } else {
      canvas.drawCircle(Offset(headCenter.dx + 5, headCenter.dy - 2), 2.2, Paint()..color = const Color(0xFF2B2B2B));
      canvas.drawCircle(Offset(headCenter.dx + 5.8, headCenter.dy - 2.8), 0.8, Paint()..color = Colors.white);
    }
  }

  void _paintDog(Canvas canvas, Size size) {
    const bodyCol = Color(0xFFC99560);
    const bellyCol = Color(0xFFF1DFC2);
    const darkCol = Color(0xFF9C6A3A);
    const earCol = Color(0xFF8E5F33);

    final isMoving = state == 'walk' || state == 'run';
    final isSitting = state == 'sit';
    final isSleeping = state == 'sleep';

    final cycle = animValue * 2 * pi;
    final maxAngle = (state == 'run') ? 0.75 : 0.44;
    final bob = isMoving ? (sin(animValue * 4 * pi).abs() * (state == 'run' ? 3.0 : 1.9)) : 0.0;

    // Diagonal trot gait
    final hindFarAngle = isMoving ? sin(cycle) * maxAngle : (state == 'jump' ? -0.52 : 0.0);
    final frontNearAngle = isMoving ? sin(cycle) * maxAngle : (state == 'jump' ? 0.48 : 0.0);
    final hindNearAngle = isMoving ? -sin(cycle) * maxAngle : (state == 'jump' ? -0.48 : 0.0);
    final frontFarAngle = isMoving ? -sin(cycle) * maxAngle : (state == 'jump' ? 0.52 : 0.0);

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(36, 54), width: isSleeping ? 38 : 44, height: 6),
      Paint()..color = const Color(0x28000000),
    );

    // 1. Far legs
    _drawArticulatedLeg(
      canvas,
      joint: Offset(22, 38 - bob),
      angle: hindFarAngle,
      color: darkCol,
      length: 15,
      width: 6.0,
      isHind: true,
      state: state,
      isSitting: isSitting,
      isSleeping: isSleeping,
    );
    _drawArticulatedLeg(
      canvas,
      joint: Offset(46, 38 - bob),
      angle: frontFarAngle,
      color: darkCol,
      length: 15,
      width: 6.0,
      isHind: false,
      state: state,
      isSitting: isSitting,
      isSleeping: isSleeping,
    );

    // 2. Tail (wagging fast and happily!)
    final tailPaint = Paint()
      ..color = bodyCol
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final wag = sin(animValue * 4 * pi) * 12.0;
    final tailPath = Path()
      ..moveTo(17, 38 - bob)
      ..cubicTo(12, 34 - bob, 10 + wag, 24 - bob, 14 + wag, 20 - bob);
    canvas.drawPath(tailPath, tailPaint);

    // 3. Body & Belly
    canvas.drawOval(
      Rect.fromCenter(center: Offset(35, 40 - bob), width: 38, height: 22),
      Paint()..color = bodyCol,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(37, 44 - bob), width: 24, height: 11),
      Paint()..color = bellyCol,
    );

    // 4. Near legs
    _drawArticulatedLeg(
      canvas,
      joint: Offset(22, 38 - bob),
      angle: hindNearAngle,
      color: bodyCol,
      length: 15,
      width: 6.0,
      isHind: true,
      state: state,
      isSitting: isSitting,
      isSleeping: isSleeping,
    );
    _drawArticulatedLeg(
      canvas,
      joint: Offset(46, 38 - bob),
      angle: frontNearAngle,
      color: bodyCol,
      length: 15,
      width: 6.0,
      isHind: false,
      state: state,
      isSitting: isSitting,
      isSleeping: isSleeping,
    );

    // 5. Head
    final headCenter = Offset(52, 28 - bob);
    canvas.drawCircle(headCenter, 11, Paint()..color = bodyCol);

    // Floppy Ear
    canvas.save();
    canvas.translate(headCenter.dx - 6, headCenter.dy + 1);
    canvas.rotate((18 + sin(animValue * 4 * pi) * 6) * pi / 180);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 9, height: 18), Paint()..color = earCol);
    canvas.restore();

    // Snout
    canvas.drawOval(
      Rect.fromCenter(center: Offset(headCenter.dx + 8, headCenter.dy + 4), width: 14, height: 10),
      Paint()..color = bellyCol,
    );
    canvas.drawCircle(Offset(headCenter.dx + 13, headCenter.dy + 2), 2.4, Paint()..color = const Color(0xFF2B2B2B));

    // Eye
    if (isSleeping) {
      final sleepEye = Path()
        ..moveTo(headCenter.dx + 2, headCenter.dy - 2)
        ..quadraticBezierTo(headCenter.dx + 5, headCenter.dy + 1, headCenter.dx + 8, headCenter.dy - 2);
      canvas.drawPath(sleepEye, Paint()..color = const Color(0xFF2B2B2B)..style = PaintingStyle.stroke..strokeWidth = 1.4);
    } else {
      canvas.drawCircle(Offset(headCenter.dx + 4.5, headCenter.dy - 2), 2.2, Paint()..color = const Color(0xFF2B2B2B));
      canvas.drawCircle(Offset(headCenter.dx + 5.2, headCenter.dy - 2.8), 0.8, Paint()..color = Colors.white);
    }
  }

  void _paintRabbit(Canvas canvas, Size size) {
    const bodyCol = Color(0xFFEFE9E1);
    const bellyCol = Colors.white;
    const darkCol = Color(0xFFD6CDC2);
    const earCol = Color(0xFFF4B6C0);

    final isMoving = state == 'walk' || state == 'run';
    final isSitting = state == 'sit';
    final isSleeping = state == 'sleep';

    // Rabbit Hop Dynamics:
    // When moving, both hind legs push together, body arches up, and front paws reach forward!
    double hopBob = 0.0;
    double hindAngle = 0.0;
    double frontAngle = 0.0;
    double earTilt = 0.0;

    if (isMoving) {
      final t = animValue; // 0.0 to 1.0
      // Leap phase is between 0.15 and 0.70
      if (t >= 0.15 && t <= 0.70) {
        final p = sin((t - 0.15) / 0.55 * pi);
        hopBob = -p * (state == 'run' ? 7.5 : 4.5);
        hindAngle = -p * (state == 'run' ? 0.85 : 0.55); // push back
        frontAngle = p * (state == 'run' ? 0.65 : 0.40); // reach forward
        earTilt = -p * 0.25; // ears stream back in wind
      } else if (t > 0.70) {
        final p = (1.0 - t) / 0.30;
        frontAngle = -p * 0.2; // landing paws touch down
        hindAngle = p * 0.3; // hind feet gather forward
      }
    } else if (state == 'jump') {
      hopBob = -5.0;
      hindAngle = -0.65;
      frontAngle = 0.5;
      earTilt = -0.2;
    }

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(36, 54), width: isSleeping ? 34 : 40, height: 6),
      Paint()..color = const Color(0x28000000),
    );

    // Fluffy cotton tail
    canvas.drawCircle(Offset(14, 38 + hopBob), 6, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(14, 38 + hopBob), 6, Paint()..color = darkCol..style = PaintingStyle.stroke..strokeWidth = 1);

    // 1. Far Hind Leg
    if (isSitting) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(20, 42), width: 16, height: 13),
        Paint()..color = darkCol,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(18, 48, 14, 5), const Radius.circular(2.5)),
        Paint()..color = darkCol,
      );
    } else if (isSleeping) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(22, 44), width: 14, height: 8),
        Paint()..color = darkCol,
      );
    } else {
      // Hopping hind leg (far)
      canvas.save();
      canvas.translate(22, 38 + hopBob);
      canvas.rotate(hindAngle);
      final hindPath = Path()
        ..moveTo(-4, 0)
        ..lineTo(4, 0)
        ..lineTo(3, 11)
        ..lineTo(8, 15)
        ..lineTo(-4, 15)
        ..lineTo(-2, 11)
        ..close();
      canvas.drawPath(hindPath, Paint()..color = darkCol);
      canvas.restore();
    }

    // 2. Far Front Paw
    if (isSitting) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(44, 46), width: 6, height: 9),
        Paint()..color = darkCol,
      );
    } else if (!isSleeping) {
      canvas.save();
      canvas.translate(46, 39 + hopBob);
      canvas.rotate(frontAngle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-2.5, 0, 5, 14), const Radius.circular(2.5)),
        Paint()..color = darkCol,
      );
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(0.5, 14), width: 6.5, height: 3.5),
        Paint()..color = darkCol,
      );
      canvas.restore();
    }

    // 3. Body
    canvas.drawOval(
      Rect.fromCenter(center: Offset(34, 40 + hopBob), width: 34, height: 20),
      Paint()..color = bodyCol,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(36, 44 + hopBob), width: 22, height: 10),
      Paint()..color = bellyCol,
    );

    // 4. Near Hind Leg
    if (isSitting) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(20, 42), width: 16, height: 13),
        Paint()..color = bodyCol,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(18, 48, 14, 5), const Radius.circular(2.5)),
        Paint()..color = bodyCol,
      );
    } else if (isSleeping) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(24, 45), width: 14, height: 8),
        Paint()..color = bodyCol,
      );
    } else {
      // Hopping hind leg (near)
      canvas.save();
      canvas.translate(22, 38 + hopBob);
      canvas.rotate(hindAngle);
      final hindPath = Path()
        ..moveTo(-4, 0)
        ..lineTo(4, 0)
        ..lineTo(3, 11)
        ..lineTo(8, 15)
        ..lineTo(-4, 15)
        ..lineTo(-2, 11)
        ..close();
      canvas.drawPath(hindPath, Paint()..color = bodyCol);
      canvas.restore();
    }

    // 5. Near Front Paw
    if (isSitting) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(46, 46), width: 6, height: 9),
        Paint()..color = bodyCol,
      );
    } else if (isSleeping) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(43, 46), width: 8, height: 6),
        Paint()..color = bodyCol,
      );
    } else {
      canvas.save();
      canvas.translate(46, 39 + hopBob);
      canvas.rotate(frontAngle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-2.5, 0, 5, 14), const Radius.circular(2.5)),
        Paint()..color = bodyCol,
      );
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(0.5, 14), width: 6.5, height: 3.5),
        Paint()..color = bodyCol,
      );
      canvas.restore();
    }

    // 6. Head
    final headCenter = Offset(50, 28 + hopBob);
    canvas.drawCircle(headCenter, 10, Paint()..color = bodyCol);

    // Tall Ears (flutter during hop)
    canvas.save();
    canvas.translate(headCenter.dx - 3, headCenter.dy - 12);
    canvas.rotate((-8 * pi / 180) + earTilt);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 7, height: 18), Paint()..color = bodyCol);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 4, height: 14), Paint()..color = earCol);
    canvas.restore();

    canvas.save();
    canvas.translate(headCenter.dx + 4, headCenter.dy - 12);
    canvas.rotate((8 * pi / 180) + earTilt);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 7, height: 18), Paint()..color = bodyCol);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 4, height: 14), Paint()..color = earCol);
    canvas.restore();

    // Nose (twitches cutely)
    final noseTwitch = (isSitting || state == 'lick') ? sin(animValue * 6 * pi) * 0.6 : 0.0;
    canvas.drawCircle(Offset(headCenter.dx + 8, headCenter.dy + 3 + noseTwitch), 1.8, Paint()..color = const Color(0xFFE8788A));

    // Eye
    if (isSleeping) {
      final sleepEye = Path()
        ..moveTo(headCenter.dx + 1, headCenter.dy - 2)
        ..quadraticBezierTo(headCenter.dx + 4, headCenter.dy + 1, headCenter.dx + 7, headCenter.dy - 2);
      canvas.drawPath(sleepEye, Paint()..color = const Color(0xFF2B2B2B)..style = PaintingStyle.stroke..strokeWidth = 1.4);
    } else {
      canvas.drawCircle(Offset(headCenter.dx + 3.5, headCenter.dy - 2), 2.0, Paint()..color = const Color(0xFF2B2B2B));
      canvas.drawCircle(Offset(headCenter.dx + 4.1, headCenter.dy - 2.6), 0.7, Paint()..color = Colors.white);
    }
  }

  void _paintBird(Canvas canvas, Size size) {
    const bodyCol = Color(0xFF5AA7E0);
    const bellyCol = Color(0xFFF3E3B8);
    const wingCol = Color(0xFF3F84C0);
    const wingDarkCol = Color(0xFF2C6498);
    const beakCol = Color(0xFFF2A03D);
    const legCol = Color(0xFFC98A3D);

    final isFlying = state == 'fly' || state == 'jump';
    final isMoving = state == 'walk';
    final isSleeping = state == 'sleep';

    // In flight:
    // - Wings flap vigorously with sin(animValue * 8 * pi) * 0.95 rad
    // - Legs are neatly tucked under belly
    // - Shadow is omitted/faded
    // On ground:
    // - Spindly legs with spread claw toes
    // - Two-footed hop bobbing
    final hop = isMoving ? (sin(animValue * 4 * pi).abs() * 3.5) : 0.0;
    final flapAngle = isFlying
        ? sin(animValue * 8 * pi) * 0.95
        : (state == 'naughty' ? sin(animValue * 6 * pi) * 0.5 : 0.0);

    // Shadow (only on ground or low hop)
    if (!isFlying) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(36, 54), width: 32, height: 5),
        Paint()..color = const Color(0x28000000),
      );
    }

    final legPaint = Paint()
      ..color = legCol
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    if (isFlying) {
      // Feet are curled up under the belly in flight!
      canvas.drawLine(const Offset(32, 45), const Offset(35, 47), legPaint);
      canvas.drawLine(const Offset(35, 47), const Offset(38, 45), legPaint);
      canvas.drawLine(const Offset(37, 45), const Offset(40, 47), legPaint);
    } else if (isSleeping) {
      // Feet hidden under resting feathers
    } else {
      // Two little legs with 3 claw toes on ground
      canvas.drawLine(Offset(32, 46 - hop), Offset(32, 53), legPaint);
      canvas.drawLine(Offset(39, 46 - hop), Offset(39, 53), legPaint);
      // Toes
      canvas.drawLine(Offset(29, 53), Offset(34, 53), legPaint);
      canvas.drawLine(Offset(36, 53), Offset(41, 53), legPaint);
    }

    // Tail feathers
    final tail = Path();
    if (isFlying) {
      // Fanned out for flight steering
      tail
        ..moveTo(23, 38)
        ..lineTo(3, 48)
        ..lineTo(10, 39)
        ..lineTo(1, 36)
        ..lineTo(10, 33)
        ..lineTo(4, 25)
        ..lineTo(23, 33)
        ..close();
    } else {
      tail
        ..moveTo(22, 40 - hop)
        ..lineTo(4, 48 - hop)
        ..lineTo(10, 38 - hop)
        ..lineTo(2, 36 - hop)
        ..lineTo(22, 33 - hop)
        ..close();
    }
    canvas.drawPath(tail, Paint()..color = wingCol);

    // Body & Belly
    final bodyCenter = Offset(36, isFlying ? 38.0 : 38 - hop);
    canvas.drawOval(
      Rect.fromCenter(center: bodyCenter, width: 30, height: 24),
      Paint()..color = bodyCol,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(bodyCenter.dx + 6, bodyCenter.dy + 4), width: 18, height: 16),
      Paint()..color = bellyCol,
    );

    // Wing (multi-feathered and articulated)
    canvas.save();
    canvas.translate(30, bodyCenter.dy);
    if (isFlying) {
      canvas.rotate((-15 * pi / 180) + flapAngle);
      // Large layered flight wing
      final flightWing = Path()
        ..moveTo(-3, 0)
        ..cubicTo(6, -14, 18, -16, 22, -8)
        ..lineTo(18, 0)
        ..lineTo(12, 6)
        ..close();
      canvas.drawPath(flightWing, Paint()..color = wingCol);
      // Primary flight feathers trailing out
      final feathers = Path()
        ..moveTo(10, -6)
        ..lineTo(26, -14)
        ..lineTo(20, -4)
        ..lineTo(24, 0)
        ..lineTo(16, 4)
        ..close();
      canvas.drawPath(feathers, Paint()..color = wingDarkCol);
    } else {
      // Folded wing resting at side
      canvas.rotate((-18 * pi / 180) + flapAngle);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 22, height: 14), Paint()..color = wingCol);
      canvas.drawOval(Rect.fromCenter(center: const Offset(-2, 2), width: 16, height: 8), Paint()..color = wingDarkCol);
    }
    canvas.restore();

    // Head
    final headCenter = Offset(48, isFlying ? 28.0 : 28 - hop);
    canvas.drawCircle(headCenter, 9, Paint()..color = bodyCol);

    // Beak
    final beak = Path()
      ..moveTo(headCenter.dx + 6, headCenter.dy - 3)
      ..lineTo(headCenter.dx + 16, headCenter.dy)
      ..lineTo(headCenter.dx + 6, headCenter.dy + 3)
      ..close();
    canvas.drawPath(beak, Paint()..color = beakCol);

    // Eye
    if (isSleeping) {
      final sleepEye = Path()
        ..moveTo(headCenter.dx + 2, headCenter.dy - 2)
        ..quadraticBezierTo(headCenter.dx + 4.5, headCenter.dy + 1, headCenter.dx + 7, headCenter.dy - 2);
      canvas.drawPath(sleepEye, Paint()..color = const Color(0xFF2B2B2B)..style = PaintingStyle.stroke..strokeWidth = 1.4);
    } else {
      canvas.drawCircle(Offset(headCenter.dx + 4, headCenter.dy - 2), 2.0, Paint()..color = const Color(0xFF2B2B2B));
      canvas.drawCircle(Offset(headCenter.dx + 4.6, headCenter.dy - 2.6), 0.7, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _PetPainter old) =>
      old.kind != kind || old.state != state || old.animValue != animValue;
}
