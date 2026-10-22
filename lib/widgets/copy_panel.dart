import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../screens/reader_screen.dart';
import '../services/book_files.dart';
import '../theme.dart';
import 'common.dart';

/// Read / attach controls for a book's own PDF copy, shown inside book dialogs.
class CopyPanel extends StatelessWidget {
  final Item b;
  final bool editable;
  const CopyPanel(this.b, {super.key, this.editable = true});

  Future<void> _attach() async {
    final c = await pickBookCopy();
    if (c == null) return;
    await attachCopy(b, c);
    toast(c.isEpub ? 'EPUB attached' : 'Attached · ${plural(c.pages, 'page')}');
  }

  @override
  Widget build(BuildContext context) {
    if (store.copyExists(b)) {
      final pct = b.pages <= 1 ? 0.0 : (b.page / (b.pages - 1)).clamp(0.0, 1.0);
      final started = b.readAt != null;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Pill(
            started ? 'Continue reading · p. ${b.page + 1}' : 'Read your copy',
            kind: Kind.pri,
            expand: true,
            icon: const Text('📖', style: TextStyle(fontSize: 16)),
            pad: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            onTap: () {
              Navigator.of(context).pop();
              openReader(b);
            },
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct),
              duration: const Duration(milliseconds: 700),
              curve: ease,
              builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 6, color: C.brown, backgroundColor: C.chip),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(b.pages == 0 ? (b.isEpub ? 'EPUB · not opened yet' : 'Not opened yet') : 'Page ${b.page + 1} of ${b.pages} · ${(pct * 100).round()}%',
                  style: nu(12, FontWeight.w700, C.muted)),
            ),
            if (editable) ...[
              _link('Replace', _attach),
              const SizedBox(width: 12),
              _link('Remove', () {
                detachCopy(b);
                toast('Book file removed');
              }),
            ],
          ]),
        ]),
      );
    }
    if (!editable) return const SizedBox.shrink();
    final missing = b.file != null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (missing)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('This book’s file isn’t on this phone. Restore a backup that includes book files, or attach it again.', style: nu(12, FontWeight.w700, C.muted)),
          ),
        Pill(
          missing ? 'Attach the file again' : 'Have a copy? Attach a PDF or EPUB',
          kind: Kind.outline,
          expand: true,
          icon: const Text('📎', style: TextStyle(fontSize: 15)),
          pad: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
          onTap: _attach,
        ),
      ]),
    );
  }

  Widget _link(String t, VoidCallback f) => Pressable(
        onTap: f,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(t, style: nu(12, FontWeight.w800, C.brown)),
        ),
      );
}
