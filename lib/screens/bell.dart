import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../icons.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'library_screen.dart';

class BellButton extends StatelessWidget {
  const BellButton({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, _) => BadgeButton(icon: Ic.bell, count: store.bellCount, label: 'Notifications', onTap: openNotifications),
      );
}

const _tabs = [('all', 'All'), ('due', 'Due'), ('late', 'Overdue'), ('rw', 'Rewards')];

void openNotifications() {
  var f = 'all';
  openDialog((ctx) => ListenableBuilder(
        listenable: store,
        builder: (ctx, _) => StatefulBuilder(builder: (ctx, set) {
          final due = store.dueTodos;
          final rows = <Widget>[];
          if (f != 'rw') {
            for (final t in due) {
              final late = store.isOverdue(t);
              if (f == 'late' && !late) continue;
              if (f == 'due' && late) continue;
              rows.add(_row(
                dot: late ? C.error : C.brown,
                title: t.text,
                sub: '${late ? 'Overdue · ' : ''}${fmtDue(t.dueAt!)}',
                action: Pill('Done', kind: Kind.pri, size: 13, pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), onTap: () {
                  _done(t);
                }),
              ));
            }
          }
          if (f == 'all' || f == 'rw') {
            for (final r in store.unclaimed) {
              rows.add(_row(
                emoji: r.emoji,
                title: 'Reward unlocked: ${r.title}',
                sub: r.desc,
                action: Pill('Claim', size: 13, pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), onTap: () {
                  Navigator.pop(ctx);
                  openRewards();
                }),
              ));
            }
          }
          const empty = {
            'all': 'You’re all caught up.',
            'due': 'Nothing due today.',
            'late': 'Nothing overdue. Nice!',
            'rw': 'No rewards waiting. Keep reading!',
          };
          return AppDialog(
            title: 'Notifications',
            maxWidth: 380,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                child: Row(children: [
                  for (final (k, l) in _tabs)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: PopChip(l,
                            on: f == k,
                            fontSize: 12,
                            pad: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                            onTap: () => set(() => f = k)),
                      ),
                    ),
                ]),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: ease,
                child: rows.isEmpty
                    ? Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Sub(empty[f]!))
                    : ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .52),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => Divider(height: 1, color: C.line),
                          itemBuilder: (_, i) => FadeIn(delay: i * 40, dy: 8, ms: 300, child: rows[i]),
                        ),
                      ),
              ),
            ],
            actions: const [Btn('Close')],
          );
        }),
      ));
}

void _done(Todo t) {
  store.toggleTodo(t);
  Sfx.play('check');
  toast('Nice! Task done ✓');
}

Widget _row({Color? dot, String? emoji, required String title, required String sub, required Widget action}) {
  return SizedBox(
    height: 64,
    child: Row(children: [
      if (dot != null) Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
      if (emoji != null) Text(emoji, style: const TextStyle(fontSize: 20)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(14, FontWeight.w800, C.ink, 1.3)),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(12, FontWeight.w600, C.muted, 1.3)),
        ]),
      ),
      const SizedBox(width: 8),
      action,
    ]),
  );
}
