import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../art.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../look.dart';
import '../services/book_files.dart';
import '../services/notify.dart';
import '../services/updater.dart';
import '../widgets/update_card.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../version.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'library_screen.dart';
import 'tour.dart';

/// Settings, as a full page: appearance, backup, alerts and the rest.
class SettingsScreen extends StatefulWidget {
  final VoidCallback onProfile, onReplay;
  const SettingsScreen({super.key, required this.onProfile, required this.onReplay});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false, _about = false, _checking = false;
  int _customSubTab = 0;

  Future<void> _buyCoffee() async {
    Buzz.medium();
    Sfx.play('fanfare');
    final url = Uri.parse('https://buymeacoffee.com/rrajkumarpadmanabhan');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    toast('Thank you for supporting Shelfwise! ☕💛');
  }

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final r = await Updater.check(force: true);
      if (!mounted) return;
      if (r == null) {
        toast('You’re on the latest version ($appVersion)');
      } else {
        store.settings.skipVersion = '';
        openUpdate(r);
      }
    } catch (_) {
      toast('Couldn’t reach GitHub. Check your connection.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _set(void Function() f, {bool look = false}) {
    f();
    store.changed();
    if (look) Look.apply(animate: true);
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final box = context.findRenderObject() as RenderBox?;
    try {
      final f = await store.exportBackup(withCopies: store.settings.backupFiles);
      Sfx.play('swoosh');
      await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path, mimeType: f.path.endsWith('.zip') ? 'application/zip' : 'application/json')],
        subject: 'Shelfwise backup',
        text: 'My Shelfwise backup: ${plural(store.totalBooks, 'book')}, ${plural(store.todos.length, 'to-do')}. '
            'Open Shelfwise → Settings → Import backup to restore it.',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    } catch (_) {
      toast('Couldn’t create the backup');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final PlatformFile? f;
    try {
      f = await FilePicker.pickFile(type: FileType.any, dialogTitle: 'Choose a Shelfwise backup');
    } catch (_) {
      toast('Couldn’t open the file picker');
      return;
    }
    if (f == null) return;
    final BackupFile b;
    try {
      final path = f.path;
      b = path != null && File(path).existsSync() ? store.parseBackupFile(path) : store.parseBackup(await f.readAsBytes());
    } on FormatException catch (e) {
      Sfx.play('knock');
      toast(e.message);
      return;
    } catch (_) {
      toast('Couldn’t read that file');
      return;
    }
    final when = b.exportedAt == null ? '' : ', saved ${fmtDate(b.exportedAt!.millisecondsSinceEpoch)}';
    final ok = await confirm(
      'Restore this backup?',
      'It has ${plural(b.books, 'book')} on ${plural(b.shelves, 'shelf', 'shelves')} and ${plural(b.todos, 'to-do')}$when'
          '${b.copies.isEmpty ? '' : ', plus ${plural(b.copies.length, 'book file')}'}. '
          'It replaces everything on this phone right now.',
      yes: 'Restore',
      no: 'Cancel',
      kind: Kind.pri,
    );
    if (!ok) {
      await b.close();
      return;
    }
    await store.restore(b);
    await Notifier.sync();
    Sfx.play('reset');
    toast('Backup restored · welcome back, ${store.profile.first}!');
  }

  final Set<String> _openSections = {};

  Widget _section({
    required String id,
    required String emoji,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final isOpen = _openSections.contains(id);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: () {
              Buzz.tick();
              setState(() {
                if (isOpen) {
                  _openSections.remove(id);
                } else {
                  _openSections.add(id);
                }
              });
            },
            scale: .98,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isOpen ? C.brown.withValues(alpha: .35) : C.line),
                boxShadow: [
                  BoxShadow(color: Color.fromRGBO(0, 0, 0, C.dark ? .15 : .04), offset: const Offset(0, 2), blurRadius: 6),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isOpen ? C.brown.withValues(alpha: .14) : C.chip,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 19)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: nu(16, FontWeight.w800, C.ink)),
                        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(12.5, FontWeight.w600, C.muted)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: isOpen ? 0.25 : 0,
                    duration: const Duration(milliseconds: 240),
                    curve: ease,
                    child: Text('›', style: nu(22, FontWeight.w700, isOpen ? C.brown : C.muted)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: ease,
            child: isOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.settings;
        var i = 0;
        Widget sec(Widget w) => FadeIn(delay: 60 * i++, dy: 12, child: w);
        return ListView(
          padding: EdgeInsets.fromLTRB(22, mq.padding.top + 26, 22, 120),
          children: [
            sec(const H1('Settings')),
            sec(Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Make Shelfwise feel like yours', style: nu(14, FontWeight.w600, C.muted)),
            )),
            const SizedBox(height: 18),
            sec(_profileCard()),
            sec(_section(
              id: 'custom',
              emoji: '🎨',
              title: 'Custom',
              subtitle: 'Appearance, shelf style, pets & feel',
              child: CardBox(
                pad: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          for (final (ix, label, emoji) in const [
                            (0, 'Appearance', '🎨'),
                            (1, 'Shelf style', '🪵'),
                            (2, 'Pets', '🐾'),
                            (3, 'Feel', '✨'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Pressable(
                                onTap: () {
                                  Buzz.tick();
                                  setState(() => _customSubTab = ix);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _customSubTab == ix ? C.brown : C.chip,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _customSubTab == ix ? C.brown : C.line,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(emoji, style: const TextStyle(fontSize: 14)),
                                      const SizedBox(width: 6),
                                      Text(
                                        label,
                                        style: nu(13, FontWeight.w800, _customSubTab == ix ? Colors.white : C.chipText),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_customSubTab == 0)
                      _buildAppearanceSettings(s)
                    else if (_customSubTab == 1)
                      _buildShelfStyleSettings(s)
                    else if (_customSubTab == 2)
                      _buildPetsSettings(s)
                    else
                      _buildFeelSettings(s),
                  ],
                ),
              ),
            )),
            sec(Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Pressable(
                onTap: _buyCoffee,
                scale: .98,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFD54F)),
                    boxShadow: [
                      BoxShadow(color: const Color(0x1F000000), offset: const Offset(0, 2), blurRadius: 6),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFDD00),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(color: Color(0x22000000), offset: Offset(0, 1), blurRadius: 3),
                          ],
                        ),
                        child: const Text('☕', style: TextStyle(fontSize: 20)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Buy me a coffee', style: nu(16, FontWeight.w800, C.ink)),
                            Text('Support cozy reading & future Shelfwise updates',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(12.5, FontWeight.w600, C.muted)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8F00),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Support 💛', style: nu(12, FontWeight.w800, Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            )),
            sec(_section(
              id: 'backup',
              emoji: '💾',
              title: 'Backup & restore',
              subtitle: 'Export to Drive or files, include book copies & restore',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card([
                    _item('📤', 'Share backup',
                        sub: _busy ? 'Saving…' : (store.lastBackup == null ? 'Send a backup file to Drive, email or chat' : 'Last saved ${fmtDate(store.lastBackup!)}'),
                        onTap: _share),
                    _item('📚', 'Include book files',
                        sub: store.copiesBytes == 0
                            ? 'PDF and EPUB copies, when you attach some'
                            : 'Adds ${fmtSize(store.copiesBytes)} of PDF/EPUB copies',
                        trailing: AppSwitch(value: s.backupFiles, onChanged: (v) {
                          _set(() => s.backupFiles = v);
                          toast(v ? 'Backups will carry your book files' : 'Backups will skip book files');
                        })),
                    _item('📥', 'Import backup', sub: 'Restore from a Shelfwise backup file', onTap: _import),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                    child: Text(
                        'Everything stays on this phone. Backups hold your shelves, to-dos, covers, notes and progress'
                        '${s.backupFiles ? ', plus your book files (as a .zip).' : '. Turn on “Include book files” to carry your PDFs and EPUBs too.'}',
                        style: nu(12, FontWeight.w600, C.muted, 1.4)),
                  ),
                ],
              ),
            )),
            sec(_section(
              id: 'alerts',
              emoji: '🔔',
              title: 'Alerts',
              subtitle: 'To-do reminder notifications and evening nudge',
              child: _card([
                _item('🔔', 'To-do reminders', sub: 'A nudge when a to-do is due or starts soon', trailing: AppSwitch(value: s.reminders, onChanged: (v) async {
                  if (v && !await Notifier.requestPermission()) toast('Allow notifications for Shelfwise in Android settings');
                  _set(() => s.reminders = v);
                  toast(v ? 'To-do reminders on' : 'To-do reminders off');
                })),
                _item('🌙', 'Evening reading nudge', sub: 'Every day at 8 PM', trailing: AppSwitch(value: s.dailyNudge, onChanged: (v) async {
                  if (v && !await Notifier.requestPermission()) toast('Allow notifications for Shelfwise in Android settings');
                  _set(() => s.dailyNudge = v);
                  toast(v ? 'We’ll nudge you at 8 PM' : 'Evening nudge off');
                })),
              ]),
            )),
            sec(_section(
              id: 'updates',
              emoji: '🚀',
              title: 'Updates',
              subtitle: 'Version $appVersion · Check for new releases',
              child: _card([
                _item('⬆️', 'Check for updates', sub: _checking ? 'Checking…' : 'You have version $appVersion', onTap: _checkNow),
                _item('🔄', 'Check automatically', sub: 'Once a day, quietly', trailing: AppSwitch(value: s.autoUpdate, onChanged: (v) => _set(() => s.autoUpdate = v))),
              ]),
            )),
            sec(_section(
              id: 'more',
              emoji: '⭐',
              title: 'More',
              subtitle: 'Rewards, take the tour, replay intro and about',
              child: _card([
                _item('☕', 'Buy me a coffee', sub: 'Support cozy reading & future Shelfwise updates', onTap: _buyCoffee),
                _item('🎁', 'Rewards', sub: store.unclaimed.isEmpty ? 'See what’s next' : '${store.unclaimed.length} waiting for you', onTap: openRewards),
                _item('🧭', 'Take the tour', sub: 'A quick look at everything Shelfwise does', onTap: () => Navigator.of(context).push(tourRoute())),
                _item('🔁', 'Replay intro', sub: 'See the welcome screens again', onTap: widget.onReplay),
                _item('ℹ️', 'About Shelfwise', sub: 'Version $appVersion', onTap: () => setState(() => _about = !_about), open: _about),
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: ease,
                  child: _about ? _aboutBody() : const SizedBox(width: double.infinity),
                ),
              ]),
            )),
            const SizedBox(height: 26),
            Center(child: Opacity(opacity: .8, child: SvgPicture.string(owlSvg, width: 56, height: 51))),
            const SizedBox(height: 6),
            Text('Shelfwise $appVersion · made for readers', textAlign: TextAlign.center, style: nu(12, FontWeight.w700, C.muted)),
          ],
        );
      },
    );
  }

  Widget _buildAppearanceSettings(Settings s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Theme'),
      Row(children: [
        for (final (k, l) in const [('light', 'Light'), ('dark', 'Dark'), ('system', 'System')]) ...[
          Expanded(child: _ThemeTile(kind: k, label: l, on: s.theme == k, onTap: () => _set(() => s.theme = k, look: true))),
          if (k != 'system') const SizedBox(width: 10),
        ],
      ]),
      const SizedBox(height: 18),
      _label('Background'),
      LayoutBuilder(
        builder: (_, c) => Wrap(spacing: 10, runSpacing: 10, children: [
          for (final f in bgFamilies)
            _BgTile(family: f, width: (c.maxWidth - 20) / 3, on: s.bg == f.key, onTap: () => _set(() => s.bg = f.key, look: true)),
        ]),
      ),
      const SizedBox(height: 14),
      _label('Pattern'),
      Row(children: [
        for (final (k, l) in bgPatterns) ...[
          Expanded(child: _PatternTile(kind: k, label: l, on: s.pattern == k, onTap: () => _set(() => s.pattern = k, look: true))),
          if (k != bgPatterns.last.$1) const SizedBox(width: 8),
        ],
      ]),
      const SizedBox(height: 18),
      _label('Accent colour'),
      Wrap(spacing: 12, runSpacing: 10, children: [
        for (final (ix, a) in accents.indexed)
          _Swatch(accent: a, on: s.accent == ix, onTap: () => _set(() => s.accent = ix, look: true)),
      ]),
      const SizedBox(height: 18),
      _label('Font'),
      Row(children: [
        for (final (f, d) in fontChoices) ...[
          Expanded(child: _FontTile(font: f, desc: d, on: s.font == f, onTap: () => _set(() => s.font = f, look: true))),
          if (f != fontChoices.last.$1) const SizedBox(width: 10),
        ],
      ]),
      const SizedBox(height: 18),
      _label('Text size'),
      Row(children: [
        for (final (v, l) in const [(.9, 'Small'), (1.0, 'Default'), (1.12, 'Large')]) ...[
          PopChip(l,
              on: s.textScale == v,
              fontSize: 13,
              pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              onTap: () => _set(() => s.textScale = v, look: true)),
          const SizedBox(width: 8),
        ],
      ]),
      const SizedBox(height: 12),
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
          child: Text('The owl read one more chapter before bed, as owls do.',
              style: nu(15, FontWeight.w600, C.body, 1.4)),
        ),
      ),
    ]);
  }

  Widget _buildShelfStyleSettings(Settings s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Shelf material'),
      Text('Applies to every shelf in My Library and Home.', style: nu(13, FontWeight.w600, C.muted)),
      const SizedBox(height: 12),
      Row(children: [
        for (final (k, l) in const [
          ('glass', 'Glass'),
          ('wood', 'Wood'),
          ('iron', 'Iron'),
          ('plastic', 'Plastic'),
        ]) ...[
          Expanded(
            child: _ShelfStyleTile(
              kind: k,
              label: l,
              on: s.shelfStyle == k,
              onTap: () {
                _set(() => s.shelfStyle = k);
                Sfx.play('tap');
                toast('Shelf style: $l');
              },
            ),
          ),
          if (k != 'plastic') const SizedBox(width: 8),
        ],
      ]),
    ]);
  }

  Widget _buildPetsSettings(Settings s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Choose your companion'),
      Text(
        'Your pet roams your screens, hops onto shelves on Home, and visits your to-dos. Double-tap it to shoo it away.',
        style: nu(13, FontWeight.w600, C.muted),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (k, l, e) in const [
          ('none', 'No pet', '🚫'),
          ('cat', 'Cat', '🐱'),
          ('dog', 'Dog', '🐶'),
          ('rabbit', 'Rabbit', '🐰'),
          ('bird', 'Bird', '🐦'),
        ])
          _PetChoiceTile(
            kind: k,
            label: l,
            emoji: e,
            on: s.pet == k,
            onTap: () {
              _set(() => s.pet = k);
              Sfx.pet(k, 'call');
              toast(k == 'none' ? 'No pet' : '$l is on its way!');
            },
          ),
      ]),
    ]);
  }

  Widget _buildFeelSettings(Settings s) {
    return _card([
      _item('🔊', 'Sound effects', sub: 'Page turns, lamps, owls and tears', trailing: AppSwitch(value: s.sounds, onChanged: (v) {
        _set(() => s.sounds = v);
        if (v) Sfx.play('pop');
      })),
      _item('📳', 'Haptics', sub: 'Little taps under your finger', trailing: AppSwitch(value: s.haptics, onChanged: (v) {
        _set(() => s.haptics = v);
        Buzz.light();
      })),
    ]);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: nu(13, FontWeight.w800, C.chipText)),
      );

  Widget _profileCard() {
    final p = store.profile;
    return Pressable(
      onTap: widget.onProfile,
      scale: .98,
      child: CardBox(
        pad: const EdgeInsets.all(14),
        child: Row(children: [
          const MeAvatar(size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name.isEmpty ? 'Reader' : p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(18, FontWeight.w800)),
              Text('@${p.handle} · ${plural(store.totalBooks, 'book')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(13, FontWeight.w600, C.muted)),
            ]),
          ),
          Pill('Profile', kind: Kind.pri, size: 13, pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), onTap: widget.onProfile),
        ]),
      ),
    );
  }

  Widget _card(List<Widget> rows) => CardBox(
        pad: EdgeInsets.zero,
        child: Column(children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0 && r is! AnimatedSize) Divider(height: 1, color: C.line),
            r,
          ],
        ]),
      );

  Widget _item(String emoji, String title, {String? sub, VoidCallback? onTap, Widget? trailing, bool open = false}) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: nu(15, FontWeight.w800)),
            if (sub != null) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: nu(13, FontWeight.w600, C.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        trailing ??
            AnimatedRotation(
              turns: open ? .25 : 0,
              duration: const Duration(milliseconds: 220),
              child: Text('›', style: nu(22, FontWeight.w700, C.muted)),
            ),
      ]),
    );
    return onTap == null ? row : Pressable(onTap: onTap, scale: .98, child: row);
  }

  Widget _aboutBody() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Text('About Readers', style: nu(20, FontWeight.w800, C.ink)),
          ),
          const SizedBox(height: 14),
          Text('Welcome to Your Reading Sanctuary', style: nu(16, FontWeight.w800, C.brown)),
          const SizedBox(height: 6),
          Text(
            'Readers is built for people who believe that the books we choose shape the lives we live. Whether you are tracking a towering stack of fantasy epics, organizing cozy beach reads, or sharing your exact emotional state after finishing a heartbreaking novel, Readers turns your personal bookshelf into an interactive home.',
            style: nu(13.5, FontWeight.w600, C.body, 1.45),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: C.line),
          const SizedBox(height: 16),
          Text('What Makes Readers Special?', style: nu(16, FontWeight.w800, C.brown)),
          const SizedBox(height: 10),
          _aboutFeature(
            'Your Virtual Bookshelf',
            'Build shelves, add sub-shelves, decorate them with plants, lamps, and stickers, and even arrange your books just how you like them with tactile drag-and-drop mechanics.',
          ),
          _aboutFeature(
            'Vibe-Driven Discovery',
            'Move beyond star ratings. Describe books using intuitive, community-driven vibe words—from Page-turner and Slow burn to Made me cry.',
          ),
          _aboutFeature(
            'Connected Reading',
            'Follow friends, see what books they are opening next, trade recommendations, and explore what fellow readers around the world are feeling.',
          ),
          _aboutFeature(
            'Cozy by Design',
            'Enjoy a distraction-free, beautifully crafted interface complete with full dark mode support, custom shelf materials, and tactile interactions.',
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: C.line),
          const SizedBox(height: 16),
          Text('Developer & Creator', style: nu(16, FontWeight.w800, C.brown)),
          const SizedBox(height: 6),
          Text(
            'Readers was thoughtfully designed, architected, and built from the ground up by:',
            style: nu(13.5, FontWeight.w600, C.body, 1.4),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: C.brown.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.brown.withValues(alpha: .35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('R Rajkumar Padmanabhan', style: nu(16, FontWeight.w800, C.brown)),
              const SizedBox(height: 2),
              Text('Creator & Lead Developer',
                  style: nu(13, FontWeight.w700, C.muted).copyWith(fontStyle: FontStyle.italic)),
            ]),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: C.line),
          const SizedBox(height: 16),
          Text('Get in Touch & Support', style: nu(16, FontWeight.w800, C.brown)),
          const SizedBox(height: 6),
          Text(
            'Have feedback, bug reports, or feature requests? We would love to hear from you as we continue building a warmer corner of the internet for book lovers everywhere.',
            style: nu(13.5, FontWeight.w600, C.body, 1.4),
          ),
          const SizedBox(height: 16),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            Pill('🌐 Website', size: 13, onTap: () => launchUrl(Uri.parse(siteUrl), mode: LaunchMode.externalApplication)),
            Pill('⬇️ Latest version', size: 13, onTap: () => launchUrl(Uri.parse('$repoUrl/releases/latest'), mode: LaunchMode.externalApplication)),
          ]),
        ]),
      );

  Widget _aboutFeature(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 5, right: 8),
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: C.brown, shape: BoxShape.circle),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: nu(13.5, FontWeight.w600, C.body, 1.4),
                children: [
                  TextSpan(text: '$title: ', style: nu(13.5, FontWeight.w800, C.ink)),
                  TextSpan(text: body),
                ],
              ),
            ),
          ),
        ]),
      );
}

/// A mini app preview for the theme picker.
/// A background colour family, previewed in the current light/dark mode.
class _BgTile extends StatelessWidget {
  final BgFamily family;
  final double width;
  final bool on;
  final VoidCallback onTap;
  const _BgTile({required this.family, required this.width, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = palFor(family.key, C.dark);
    return Semantics(
      button: true,
      selected: on,
      label: '${family.name} background',
      child: Pressable(
        onTap: onTap,
        scale: .93,
        child: Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: width,
            height: 54,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? C.brown : C.line, width: on ? 2.5 : 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: p.bg,
                padding: const EdgeInsets.all(7),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 26, height: 5, decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(3))),
                      const Spacer(),
                      Container(height: 14, decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(5), border: Border.all(color: p.line))),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  Container(width: 12, height: 30, decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(3))),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(family.name, style: nu(12, on ? FontWeight.w800 : FontWeight.w700, on ? C.brown : C.ink)),
        ]),
      ),
    );
  }
}

class _PatternTile extends StatelessWidget {
  final String kind, label;
  final bool on;
  final VoidCallback onTap;
  const _PatternTile({required this.kind, required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: '$label pattern',
        child: Pressable(
          onTap: onTap,
          scale: .93,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 46,
              decoration: BoxDecoration(
                color: C.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: on ? C.brown : C.line, width: on ? 2.5 : 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CustomPaint(painter: PatternPainter(kind, C.ink.withValues(alpha: .22)), child: const SizedBox.expand()),
              ),
            ),
            const SizedBox(height: 5),
            Text(label, style: nu(11.5, on ? FontWeight.w800 : FontWeight.w700, on ? C.brown : C.ink)),
          ]),
        ),
      );
}

class _ThemeTile extends StatelessWidget {
  final String kind, label;
  final bool on;
  final VoidCallback onTap;
  const _ThemeTile({required this.kind, required this.label, required this.on, required this.onTap});

  Widget _mini(Pal p) => Container(
        color: p.bg,
        padding: const EdgeInsets.all(6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 26, height: 5, decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 5),
          Row(children: [
            for (final c in const [Color(0xFF1E1A14), Color(0xFFD9C493), Color(0xFFF26B2A)])
              Container(width: 9, height: 16, margin: const EdgeInsets.only(right: 2), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          ]),
          const SizedBox(height: 4),
          Container(height: 6, decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(3))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: '$label theme',
      child: Pressable(
        onTap: onTap,
        scale: .95,
        child: Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? C.brown : C.line, width: on ? 2.5 : 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: kind == 'system'
                  ? Row(children: [Expanded(child: _mini(palFor(store.settings.bg, false))), Expanded(child: _mini(palFor(store.settings.bg, true)))])
                  : SizedBox(width: double.infinity, child: _mini(palFor(store.settings.bg, kind == 'dark'))),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: nu(13, on ? FontWeight.w800 : FontWeight.w700, on ? C.brown : C.ink)),
        ]),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Accent accent;
  final bool on;
  final VoidCallback onTap;
  const _Swatch({required this.accent, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: '${accent.name} accent',
        child: Tooltip(
          message: accent.name,
          child: Pressable(
            onTap: onTap,
            scale: .85,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? accent.color : Colors.transparent, width: 2.5)),
              child: Container(
                decoration: BoxDecoration(color: accent.color, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: AnimatedScale(
                  scale: on ? 1 : 0,
                  duration: const Duration(milliseconds: 260),
                  curve: popCurve,
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ),
      );
}

class _FontTile extends StatelessWidget {
  final String font, desc;
  final bool on;
  final VoidCallback onTap;
  const _FontTile({required this.font, required this.desc, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: '$font font',
        child: Pressable(
          onTap: onTap,
          scale: .95,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? C.brown.withValues(alpha: .12) : C.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? C.brown : C.line, width: on ? 2 : 1),
            ),
            child: Column(children: [
              Text('Aa', style: TextStyle(fontFamily: font, fontSize: 24, fontWeight: FontWeight.w700, color: on ? C.brown : C.ink)),
              Text(font, style: TextStyle(fontFamily: font, fontSize: 12, fontWeight: FontWeight.w700, color: C.ink)),
              Text(desc, style: nu(11, FontWeight.w600, C.muted)),
            ]),
          ),
        ),
      );
}

class _ShelfStyleTile extends StatelessWidget {
  final String kind;
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _ShelfStyleTile({required this.kind, required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: .94,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: on ? C.brown.withValues(alpha: .12) : C.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? C.brown : C.line, width: on ? 2 : 1),
        ),
        child: Column(children: [
          Container(
            width: double.infinity,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: switch (kind) {
                'wood' => const LinearGradient(colors: [Color(0xFFD49B62), Color(0xFFA8713B), Color(0xFF6E431F)]),
                'iron' => const LinearGradient(colors: [Color(0xFF7E8691), Color(0xFF454B52), Color(0xFF22262A)]),
                'plastic' => const LinearGradient(colors: [Color(0xFFF48AA0), Color(0xFFE56A88)]),
                _ => const LinearGradient(colors: [Color(0xFFB5D4E8), Color(0xFF8BBCE0)]),
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: nu(13, FontWeight.w800, on ? C.brown : C.ink)),
        ]),
      ),
    );
  }
}

class _PetChoiceTile extends StatelessWidget {
  final String kind;
  final String label;
  final String emoji;
  final bool on;
  final VoidCallback onTap;
  const _PetChoiceTile({required this.kind, required this.label, required this.emoji, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: .94,
      child: Container(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: on ? C.brown.withValues(alpha: .14) : C.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? C.brown : C.line, width: on ? 2 : 1),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: nu(13, FontWeight.w800, on ? C.brown : C.ink)),
        ]),
      ),
    );
  }
}
