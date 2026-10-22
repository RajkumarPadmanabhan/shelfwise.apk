import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/sfx.dart';
import '../services/updater.dart';
import '../theme.dart';
import 'common.dart';
import 'dialogs.dart';

/// Release notes without Markdown symbols, for showing in the app.
String plainNotes(String md) => md
    .split('\n')
    .where((l) => !l.trim().startsWith('SHA-256'))
    .map((l) => l.replaceAll(RegExp(r'^#+\s*'), '').replaceAll(RegExp(r'\*\*|`|__'), '').replaceAll(RegExp(r'^\s*[-*]\s+'), '• '))
    .join('\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// "Shelfwise 1.3 is ready" on Home.
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Release?>(
      valueListenable: Updater.available,
      builder: (_, r, _) {
        final show = r != null && r.version != store.settings.skipVersion;
        return AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: ease,
          child: !show
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: FadeIn(
                    child: Pressable(
                      onTap: () => openUpdate(r),
                      scale: .98,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(colors: [Color(0xFF1C1C1C), Color(0xFF3A2416)]),
                        ),
                        child: Row(children: [
                          const Text('🎉', style: TextStyle(fontSize: 28)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Shelfwise ${r.version} is ready', style: nu(15, FontWeight.w800, const Color(0xFFF7F0E6))),
                              Text('Tap to see what’s new and update', style: nu(12.5, FontWeight.w700, const Color(0xFFCDBFAE))),
                            ]),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(color: C.orange, borderRadius: BorderRadius.circular(16)),
                            child: Text('Update', style: nu(13, FontWeight.w800, Colors.white)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

void openUpdate(Release r) {
  double? progress;
  String err = '';
  openDialog((ctx) => StatefulBuilder(
        builder: (ctx, set) => AppDialog(
          title: 'Shelfwise ${r.version} is ready 🎉',
          maxWidth: 380,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .38),
              child: SingleChildScrollView(child: Text(plainNotes(r.notes), style: nu(14, FontWeight.w600, C.body, 1.45))),
            ),
            if (progress != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(value: progress, minHeight: 8, color: C.brown, backgroundColor: C.chip),
              ),
              const SizedBox(height: 6),
              Text(progress! >= 1 ? 'Opening the installer…' : 'Downloading… ${(progress! * 100).round()}%',
                  style: nu(12.5, FontWeight.w800, C.muted)),
            ],
            ErrText(err),
          ],
          actions: [
            Btn('Later', onTap: () {
              store.settings.skipVersion = r.version;
              store.changed();
              return true;
            }),
            Btn(progress == null ? 'Update now' : 'Downloading…', kind: Kind.pri, onTap: () async {
              if (progress != null) return false;
              set(() {
                progress = 0;
                err = '';
              });
              final e = await Updater.install(r, (p) => set(() => progress = p));
              if (e != null) {
                set(() {
                  progress = null;
                  err = e;
                });
                Sfx.play('knock');
                return false;
              }
              return true;
            }),
          ],
        ),
      ), dismissible: false);
}
