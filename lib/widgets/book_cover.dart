import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../art.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../theme.dart';

/// A book cover: coloured from the title (or the uploaded image), with a spine shade.
class BookCover extends StatelessWidget {
  final Item b;
  final double w, h;
  final double radius;
  final double titleSize;
  final double authorSize;
  final double shine; // 0..1 sweep progress; <=0 hides it
  final int titleLines;
  final double topBorder;
  const BookCover(this.b,
      {super.key,
      required this.w,
      required this.h,
      this.radius = 5,
      this.titleSize = 12,
      this.authorSize = 9,
      this.shine = 0,
      this.titleLines = 4,
      this.topBorder = 5});

  @override
  Widget build(BuildContext context) {
    return CoverFace(
      title: b.title,
      author: b.author,
      image: b.cover,
      w: w,
      h: h,
      radius: radius,
      titleSize: titleSize,
      authorSize: authorSize,
      shine: shine,
      titleLines: titleLines,
      topBorder: topBorder,
      status: b.status,
      hasCopy: b.hasCopy,
    );
  }
}

class CoverFace extends StatelessWidget {
  final String title, author;
  final String? image;
  final double w, h, radius, titleSize, authorSize, shine, topBorder;
  final int titleLines;
  final double spine;
  final String status;
  final bool hasCopy;
  const CoverFace(
      {super.key,
      required this.title,
      required this.author,
      this.image,
      required this.w,
      required this.h,
      this.radius = 5,
      this.titleSize = 12,
      this.authorSize = 9,
      this.shine = 0,
      this.titleLines = 4,
      this.topBorder = 5,
      this.spine = 7,
      this.status = '',
      this.hasCopy = false});

  @override
  Widget build(BuildContext context) {
    final pal = coverFor(title.isEmpty ? 'Untitled' : title);
    final file = image == null ? null : store.imageFile(image!);
    final hasImg = file != null && file.existsSync();
    return SizedBox(
      width: w,
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(fit: StackFit.expand, children: [
          if (hasImg)
            Image.file(file, fit: BoxFit.cover, gaplessPlayback: true)
          else
            Container(
              decoration: BoxDecoration(
                color: pal[0],
                border: pal.length > 2 ? Border(top: BorderSide(color: pal[2], width: topBorder)) : null,
              ),
              padding: EdgeInsets.symmetric(horizontal: w * .07, vertical: h * .06),
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(title.isEmpty ? 'Untitled' : title,
                    textAlign: TextAlign.center,
                    maxLines: titleLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: F.serif, fontWeight: FontWeight.w700, fontSize: titleSize, color: pal[1], height: 1.1)),
                if (author.isNotEmpty) ...[
                  SizedBox(height: h * .05),
                  Opacity(
                    opacity: .85,
                    child: Text(author,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: nu(authorSize, FontWeight.w700, pal[1], 1.1)),
                  ),
                ],
              ]),
            ),
          // spine shade
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: spine,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color.fromRGBO(0, 0, 0, .28), Color.fromRGBO(255, 255, 255, .12), Color(0x00FFFFFF)],
                  stops: [0, .55, 1],
                ),
              ),
            ),
          ),
          // Status Bookmark: only reading books get a bookmark, not finished books
          if (status == 'r')
            Positioned(
              top: 0,
              right: w * .12,
              width: max(10, w * .15),
              height: max(18, h * .24),
              child: const CustomPaint(
                painter: _StatusBookmark(finished: false),
              ),
            ),
          if (hasCopy)
            Positioned(
              top: 0,
              left: w * .10,
              width: max(6, w * .09),
              height: max(10, h * .14),
              child: CustomPaint(painter: _Ribbon()),
            ),
          if (shine > 0 && shine < 1)
            FractionalTranslation(
              translation: Offset(-1.3 + 2.6 * shine, 0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1, -.45),
                    end: Alignment(1, .45),
                    colors: [Color(0x00FFFFFF), Color(0x80FFFFFF), Color(0x00FFFFFF)],
                    stops: [.3, .5, .7],
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _StatusBookmark extends CustomPainter {
  final bool finished;
  const _StatusBookmark({required this.finished});

  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w / 2, h * .75)
      ..lineTo(0, h)
      ..close();

    c.drawShadow(p, Colors.black.withValues(alpha: .5), 3, false);

    final gradient = finished
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFD54F), Color(0xFFFFA000), Color(0xFFE65100)],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF7043), Color(0xFFF4511E), Color(0xFFBF360C)],
          );

    final paint = Paint()..shader = gradient.createShader(Rect.fromLTWH(0, 0, w, h));
    c.drawPath(p, paint);

    final stitchPaint = Paint()
      ..color = (finished ? const Color(0xFFFFF9C4) : const Color(0xFFFFCCBC)).withValues(alpha: .75)
      ..strokeWidth = max(0.8, w * 0.08)
      ..style = PaintingStyle.stroke;
    final leftX = w * 0.18;
    final rightX = w * 0.82;
    c.drawLine(Offset(leftX, 0), Offset(leftX, h * 0.65), stitchPaint);
    c.drawLine(Offset(rightX, 0), Offset(rightX, h * 0.65), stitchPaint);

    if (finished && w >= 10) {
      final markPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = max(1.2, w * 0.12)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final check = Path()
        ..moveTo(w * 0.28, h * 0.40)
        ..lineTo(w * 0.46, h * 0.52)
        ..lineTo(w * 0.74, h * 0.28);
      c.drawPath(check, markPaint);
    }
  }

  @override
  bool shouldRepaint(_StatusBookmark old) => old.finished != finished;
}

class _Ribbon extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(s.width / 2, s.height * .78)
      ..lineTo(0, s.height)
      ..close();
    c.drawShadow(p, Colors.black, 2, false);
    c.drawPath(p, Paint()..color = const Color(0xFFF26A21));
  }

  @override
  bool shouldRepaint(_) => false;
}

/// A shelf decoration (flowerpot, lamp, owl...). Lamps and candles glow when lit.
class GadgetView extends StatelessWidget {
  final String kind;
  final double w, h;
  final bool lit;
  const GadgetView(this.kind, {super.key, required this.w, required this.h, this.lit = false});

  @override
  Widget build(BuildContext context) {
    final g = gadgets[kind] ?? gadgets['pot']!;
    final pic = SvgPicture.string(g.svg, width: w, height: h, fit: BoxFit.contain, alignment: Alignment.bottomCenter);
    return SizedBox(
      width: w,
      height: h,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
        Positioned(
          left: -w * .35,
          right: -w * .35,
          top: -h * .3,
          bottom: h * .05,
          child: AnimatedOpacity(
            opacity: lit ? 1 : 0,
            duration: const Duration(milliseconds: 350),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color.fromRGBO(255, 214, 120, .6), Color.fromRGBO(255, 214, 120, 0)], stops: [0, .62]),
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: lit
              ? ColorFiltered(
                  key: const ValueKey(1),
                  colorFilter: const ColorFilter.matrix([1.1, 0, 0, 0, 12, 0, 1.1, 0, 0, 8, 0, 0, 1.05, 0, 0, 0, 0, 0, 1, 0]),
                  child: pic,
                )
              : KeyedSubtree(key: const ValueKey(0), child: pic),
        ),
      ]),
    );
  }
}

double gadgetHeightFactor(String kind) => (gadgets[kind] ?? gadgets['pot']!).h;

/// On a shelf behind the glass band, decorations are drawn a bit taller than in the mockup
/// so their tops show above the glass the way the books' do.
double shelfGadgetFactor(String kind) => (gadgetHeightFactor(kind) * 1.35).clamp(.62, .95);
String gadgetName(String kind) => (gadgets[kind] ?? gadgets['pot']!).name;
