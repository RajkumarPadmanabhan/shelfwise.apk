import 'package:flutter/material.dart';

import '../services/sfx.dart';
import '../theme.dart';

const starGold = Color(0xFFF2A04A);

/// Five tappable stars. Tapping the current rating again clears it.
class StarRating extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;
  final double size;
  final Color? empty;
  const StarRating({super.key, required this.value, this.onChanged, this.size = 28, this.empty});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: value == 0 ? 'Not rated' : 'Rated $value out of 5',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onChanged == null
                ? null
                : () {
                    Buzz.tick();
                    Sfx.play(i == value ? 'tap' : 'pop');
                    onChanged!(i == value ? 0 : i);
                  },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: size * .06),
              child: TweenAnimationBuilder<double>(
                key: ValueKey('${i <= value}'),
                tween: Tween(begin: i <= value ? .55 : 1, end: 1),
                duration: Duration(milliseconds: 260 + i * 50),
                curve: popCurve,
                builder: (_, s, c) => Transform.scale(scale: s, child: c),
                child: Icon(
                  i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  color: i <= value ? starGold : (empty ?? C.muted.withValues(alpha: .6)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
