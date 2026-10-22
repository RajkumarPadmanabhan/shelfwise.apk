import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../art.dart';
import '../data/models.dart';
import '../data/posts_models.dart';
import '../data/store.dart';
import '../icons.dart';
import '../services/notify.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'bell.dart';
import 'library_screen.dart';

class ProfileScreen extends StatelessWidget {
  final void Function(int tab) go;
  const ProfileScreen({super.key, required this.go});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.profile;
        return ListView(
          padding: EdgeInsets.fromLTRB(22, mq.padding.top + 24, 22, 110),
          children: [
            Row(children: [const Expanded(child: H1('Profile')), const BellButton()]),
            const SizedBox(height: 18),
            Center(
              child: SizedBox(
                width: 108,
                height: 108,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                    child: p.photo != null && store.imageFile(p.photo!).existsSync()
                        ? const MeAvatar(size: 108, border: true)
                        : Padding(padding: const EdgeInsets.only(top: 4), child: SvgPicture.string(owlSvg, width: 108, height: 100)),
                  ),
                  Positioned(
                    right: -2,
                    bottom: 4,
                    child: Semantics(
                      button: true,
                      label: 'Change photo',
                      child: Pressable(
                        onTap: _photoMenu,
                        scale: .88,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(color: C.brown, shape: BoxShape.circle, border: Border.all(color: C.bg, width: 3)),
                          alignment: Alignment.center,
                          child: const SvgIcon(Ic.camera, color: Colors.white, size: 15, stroke: 2.2),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Text(p.name.isEmpty ? 'Reader' : p.name, textAlign: TextAlign.center, style: nu(25, FontWeight.w800)),
            Text('@${p.handle}', textAlign: TextAlign.center, style: nu(14, FontWeight.w600, C.muted)),
            if (p.email.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.alternate_email_rounded, size: 13, color: C.muted),
                  const SizedBox(width: 4),
                  Text(p.email, textAlign: TextAlign.center, style: nu(13, FontWeight.w600, C.muted)),
                ]),
              ),
            if (p.bio.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(p.bio, textAlign: TextAlign.center, style: nu(14, FontWeight.w600, C.body, 1.4)),
              ),
            _socials(p),
            const SizedBox(height: 18),
            Row(children: [
              _stat(store.totalBooks, 'Books added', () => go(1)),
              const SizedBox(width: 10),
              _stat(store.finishedCount, 'Finished', () => go(3)),
              const SizedBox(width: 10),
              _stat(store.todosDone, 'To-dos done', () => go(2)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Pill('Edit profile', kind: Kind.pri, size: 14, expand: true, onTap: _edit, pad: const EdgeInsets.symmetric(vertical: 12, horizontal: 6))),
              const SizedBox(width: 10),
              Expanded(child: Pill('+ Add book', size: 14, expand: true, onTap: () => openAddBook(), pad: const EdgeInsets.symmetric(vertical: 12, horizontal: 6))),
              const SizedBox(width: 10),
              Expanded(child: Pill('Social', size: 14, expand: true, onTap: _social, pad: const EdgeInsets.symmetric(vertical: 12, horizontal: 6))),
            ]),
            if (store.claimed.isNotEmpty) ...[
              const H2('Badges'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (i, r) in rewards.where((r) => store.claimed.contains(r.id)).indexed)
                  FadeIn(
                    delay: i * 60,
                    child: Tooltip(
                      message: r.desc,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
                        child: Text('${r.emoji} ${r.title}', style: nu(13, FontWeight.w800, C.chipText)),
                      ),
                    ),
                  ),
              ]),
            ],
            const H2('My shelves'),
            if (store.totalBooks == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('No books yet. Tap “+ Add book” to start your first shelf.',
                    textAlign: TextAlign.center, style: nu(14, FontWeight.w700, C.muted)),
              )
            else
              for (final c in store.cols.where((c) => c.books.isNotEmpty)) _shelf(c),
            const H2('My posts'),
            if (store.posts.where((p) => p.mine).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No posts yet. Share your thoughts on a book from the Explore tab.',
                    textAlign: TextAlign.center, style: nu(13.5, FontWeight.w700, C.muted)),
              )
            else
              for (final p in store.posts.where((p) => p.mine))
                _profilePostCard(context, p),
            const H2('Reminders & sounds'),
            CardBox(
              pad: EdgeInsets.zero,
              child: Column(children: [
                _switchRow('🔔', 'To-do reminders', 'A nudge when a to-do is due', store.settings.reminders, (v) async {
                  if (v && !await Notifier.requestPermission()) {
                    toast('Allow notifications for Shelfwise in Android settings');
                  }
                  store.settings.reminders = v;
                  store.changed();
                  toast(v ? 'To-do reminders on' : 'To-do reminders off');
                }),
                Divider(height: 1, color: C.line),
                _switchRow('🔊', 'Sound effects', 'Taps, tears, lamps and owls', store.settings.sounds, (v) {
                  store.settings.sounds = v;
                  store.changed();
                  if (v) Sfx.play('pop');
                  toast(v ? 'Sound effects on' : 'Sound effects off');
                }),
              ]),
            ),
            const H2('Account & data'),
            CardBox(
              pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDE8E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.person_off_rounded, color: Color(0xFFDC2626), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('User Account', style: nu(15, FontWeight.w800)),
                            Text(
                              p.email.isNotEmpty ? p.email : '@${p.handle}',
                              style: nu(12.5, FontWeight.w600, C.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Delete your user account, all saved books, reading progress, and to-do lists.',
                    style: nu(12.5, FontWeight.w600, C.muted, 1.35),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Pressable(
                          onTap: () => _confirmDeleteUser(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDE8E8),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFF87171)),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.delete_forever_rounded, size: 17, color: Color(0xFFDC2626)),
                                const SizedBox(width: 6),
                                Text('Delete user', style: nu(13.5, FontWeight.w800, const Color(0xFFDC2626))),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Pressable(
                          onTap: () => _confirmLogout(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: C.chip,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: C.line),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.logout_rounded, size: 17, color: C.ink),
                                const SizedBox(width: 6),
                                Text('Logout', style: nu(13.5, FontWeight.w800, C.ink)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteUser(BuildContext context) {
    Buzz.medium();
    Sfx.play('tear');
    openDialog((ctx) => AppDialog(
          title: 'Delete user account?',
          children: [
            const Sub(
              'This action is irreversible. All your books, reading bookmarks, to-do lists, and profile data will be permanently wiped from this device.',
              pad: EdgeInsets.zero,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDE8E8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF87171)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Everything related to this user will be deleted and you will be returned to the initial setup.',
                      style: nu(12, FontWeight.w700, const Color(0xFF991B1B), 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
          actions: [
            const Btn('Cancel'),
            Btn('Delete user', kind: Kind.dng, onTap: () async {
              await store.deleteUser();
              Sfx.play('reset');
              toast('User account and all data deleted');
              return true;
            }),
          ],
        ));
  }

  void _confirmLogout(BuildContext context) {
    Buzz.tick();
    openDialog((ctx) => AppDialog(
          title: 'Log out?',
          children: [
            const Sub('You will return to the welcome screen where you can sign in or choose your library mode.'),
          ],
          actions: [
            const Btn('Cancel'),
            Btn('Logout', kind: Kind.pri, onTap: () {
              store.logout();
              toast('Logged out');
              return true;
            }),
          ],
        ));
  }

  Widget _stat(int v, String l, VoidCallback onTap) => Expanded(
        child: Pressable(
          onTap: onTap,
          child: CardBox(
            pad: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Column(children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: v.toDouble()),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (_, x, _) => Text('${x.round()}', style: nu(22, FontWeight.w800)),
              ),
              Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(12, FontWeight.w700, C.muted)),
            ]),
          ),
        ),
      );

  Widget _switchRow(String ic, String t, String s, bool v, ValueChanged<bool> on) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(ic, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: nu(15, FontWeight.w800)),
              Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(13, FontWeight.w600, C.muted)),
            ]),
          ),
          AppSwitch(value: v, onChanged: on),
        ]),
      );

  Widget _shelf(Collection c) {
    final books = c.books.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text('${c.emoji} ${c.name}', style: nu(16, FontWeight.w800))),
          Text(plural(books.length, 'book'), style: nu(12, FontWeight.w700, C.muted)),
        ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: C.plank, width: 6)),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
        ),
        child: LayoutBuilder(builder: (_, cons) {
          final w = (cons.maxWidth - 20) / 3;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final b in books)
              Pressable(
                onTap: () => openBookView(c, b),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .25), offset: Offset(0, 2), blurRadius: 6)],
                  ),
                  child: BookCover(b, w: w, h: w * 4 / 3, titleSize: 12, authorSize: 9),
                ),
              ),
          ]);
        }),
      ),
    ]);
  }

  Widget _socials(Profile p) {
    final chips = <Widget>[];
    if (p.email.isNotEmpty) chips.add(_chip('✉️ ${p.email}', 'mailto:${p.email}'));
    for (final s in p.socials) {
      if (s.v.isEmpty) continue;
      final href = socialHref(s.k, s.v);
      chips.add(_chip(href == null ? '${s.icon} ${s.k} · ${s.v}' : '${s.icon} ${s.k}', href));
    }
    if (chips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Opacity(
          opacity: .65,
          child: Text('Tap Social to add your email and links.', textAlign: TextAlign.center, style: nu(13, FontWeight.w600)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: chips),
    );
  }

  Widget _chip(String label, String? href) => Pressable(
        onTap: href == null ? null : () => launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(16)),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(13, FontWeight.w800, C.chipText)),
        ),
      );

  // ---------------- dialogs ----------------

  void _photoMenu() {
    final has = store.profile.photo != null;
    openDialog((_) => AppDialog(title: 'Profile photo', children: [
          const Sub('Pick a photo from your gallery, then drag and zoom to frame it.'),
        ], actions: [
          if (has)
            Btn('Remove photo', kind: Kind.dng, onTap: () {
              store.profile.photo = null;
              store.changed();
              toast('Photo removed');
              return true;
            }),
          const Btn('Cancel'),
          Btn('Choose photo', kind: Kind.pri, then: () async {
            final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 92);
            if (x == null) return;
            final bytes = await x.readAsBytes();
            final codec = await ui.instantiateImageCodec(bytes);
            final img = (await codec.getNextFrame()).image;
            openCrop(img);
          }),
        ]));
  }

  void _edit() {
    final p = store.profile;
    final n = TextEditingController(text: p.name), h = TextEditingController(text: p.handle), b = TextEditingController(text: p.bio);
    var err = '';
    openDialog((ctx) => StatefulBuilder(
          builder: (ctx, set) => AppDialog(title: 'Edit profile', children: [
            AppInput(n, 'Name', maxLength: 40, caps: TextCapitalization.words),
            AppInput(h, 'Username', maxLength: 30, caps: TextCapitalization.none),
            AppInput(b, 'Bio', maxLength: 140, lines: 3),
            ErrText(err),
          ], actions: [
            const Btn('Cancel'),
            Btn('Save', kind: Kind.pri, onTap: () {
              final nn = n.text.trim(), hh = h.text.trim().replaceFirst(RegExp(r'^@'), '');
              if (nn.isEmpty || hh.isEmpty) {
                set(() => err = 'Name and username are required.');
                return false;
              }
              p
                ..name = nn
                ..handle = hh
                ..bio = b.text.trim();
              store.changed();
              toast('Profile saved');
              return true;
            }),
          ]),
        ));
  }

  void _social() {
    final p = store.profile;
    final email = TextEditingController(text: p.email);
    final rows = p.socials.map((s) => (Social(s.k, s.icon, s.hint, s.v, s.custom), TextEditingController(text: s.k), TextEditingController(text: s.v))).toList();
    var err = '';
    openDialog((ctx) => StatefulBuilder(
          builder: (ctx, set) => AppDialog(title: 'Social', maxWidth: 380, children: [
            const Sub('Shown on your profile so you can find your links in one place.'),
            Text('✉️ Contact email', style: nu(13, FontWeight.w800, C.chipText)),
            AppInput(email, 'you@example.com', maxLength: 80, type: TextInputType.emailAddress, caps: TextCapitalization.none),
            for (final (s, k, v) in rows)
              if (s.custom)
                Row(children: [
                  Expanded(child: AppInput(k, 'Name', maxLength: 20)),
                  const SizedBox(width: 6),
                  Expanded(flex: 2, child: AppInput(v, 'Link or @handle', maxLength: 80, caps: TextCapitalization.none)),
                ])
              else ...[
                Padding(padding: const EdgeInsets.only(top: 8), child: Text('${s.icon} ${s.k}', style: nu(13, FontWeight.w800, C.chipText))),
                AppInput(v, s.hint, maxLength: 80, caps: TextCapitalization.none),
              ],
            ErrText(err),
          ], actions: [
            const Btn('Cancel'),
            Btn('+ Add another', onTap: () {
              if (rows.where((r) => r.$1.custom).length >= 6) {
                set(() => err = 'You can add up to 6 extra links.');
                return false;
              }
              set(() => rows.add((Social('', '🔗', 'Link', '', true), TextEditingController(), TextEditingController())));
              return false;
            }),
            Btn('Save', kind: Kind.pri, onTap: () {
              final e = email.text.trim();
              if (e.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
                set(() => err = 'Enter a valid email address.');
                return false;
              }
              for (final (s, k, v) in rows) {
                if (s.custom && (k.text.trim().isEmpty != v.text.trim().isEmpty)) {
                  set(() => err = 'Give each extra link a name and a link.');
                  return false;
                }
              }
              p.email = e;
              p.socials = [
                for (final (s, k, v) in rows)
                  if (!s.custom || k.text.trim().isNotEmpty)
                    Social(s.custom ? k.text.trim() : s.k, s.icon, s.hint, v.text.trim(), s.custom),
              ];
              store.changed();
              toast('Social links saved');
              return true;
            }),
          ]),
        ));
  }
}

String? socialHref(String k, String v) {
  v = v.trim();
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(v)) return v;
  final h = v.replaceFirst(RegExp(r'^@'), '');
  if (RegExp(r'^[\w.]+$').hasMatch(h)) {
    if (k == 'Instagram') return 'https://instagram.com/$h';
    if (k == 'X (Twitter)') return 'https://x.com/$h';
  }
  if (RegExp(r'^[\w-]+(\.[\w-]+)+(/\S*)?$').hasMatch(v)) return 'https://$v';
  return null;
}

/// Drag to reposition, slide to zoom, inside a circular mask (the mockup's canvas cropper).
void openCrop(ui.Image im) {
  const s = 280.0;
  var z = 1.0;
  var o = Offset.zero;
  Rect geo(double size) {
    final b = max(s / im.width, s / im.height) * z;
    final dw = im.width * b, dh = im.height * b;
    o = Offset(o.dx.clamp((s - dw) / 2, (dw - s) / 2), o.dy.clamp((s - dh) / 2, (dh - s) / 2));
    final k = size / s;
    return Rect.fromLTWH(((s - dw) / 2 + o.dx) * k, ((s - dh) / 2 + o.dy) * k, dw * k, dh * k);
  }

  openDialog((ctx) => StatefulBuilder(
        builder: (ctx, set) => AppDialog(title: 'Adjust your photo', maxWidth: 380, children: [
          const Sub('Drag to reposition. Use the slider to zoom.'),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GestureDetector(
                onPanUpdate: (d) => set(() => o += d.delta),
                child: SizedBox(width: s, height: s, child: CustomPaint(painter: _CropPainter(im, geo(s)))),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(activeTrackColor: C.brown, thumbColor: C.brown, inactiveTrackColor: C.chip),
            child: Slider(value: z, min: 1, max: 3, onChanged: (v) => set(() => z = v), semanticFormatterCallback: (v) => 'Zoom ${v.toStringAsFixed(1)}x'),
          ),
        ], actions: [
          const Btn('Cancel'),
          Btn('Save photo', kind: Kind.pri, onTap: () async {
            final rec = ui.PictureRecorder();
            final c = Canvas(rec);
            c.drawRect(const Rect.fromLTWH(0, 0, 320, 320), Paint()..color = C.chip);
            c.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), geo(320), Paint()..filterQuality = FilterQuality.high);
            final out = await rec.endRecording().toImage(320, 320);
            final png = await out.toByteData(format: ui.ImageByteFormat.png);
            if (png == null) return false;
            store.profile.photo = await store.saveImage(png.buffer.asUint8List(), ext: 'png');
            store.changed();
            Sfx.play('cam');
            toast('Profile photo updated');
            return true;
          }),
        ]),
      ));
}

class _CropPainter extends CustomPainter {
  final ui.Image im;
  final Rect r;
  _CropPainter(this.im, this.r);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    canvas.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), r, Paint()..filterQuality = FilterQuality.medium);
    final c = size.center(Offset.zero);
    final rad = size.width / 2 - 6;
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: c, radius: rad));
    canvas.drawPath(mask, Paint()..color = const Color.fromRGBO(0, 0, 0, .55));
    canvas.drawCircle(c, rad, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_CropPainter o) => o.r != r;
}

Widget _profilePostCard(BuildContext context, Post p) {
  final lines = p.items.where((i) => i.isLine).map((i) => i.text).toList();
  final words = p.items.where((i) => i.isWord).map((i) => i.text).toList();
  final timeStr = formatTimeAgo(p.timestamp);
  final likes = store.postLikes(p);
  final shares = store.postShares(p);

  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: C.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: C.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 44,
              decoration: BoxDecoration(
                color: C.chip,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: C.line),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.menu_book_rounded, size: 20, color: Color(0xFFF26A21)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.bookTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(14.5, FontWeight.w800, C.ink)),
                  Text(p.bookAuthor, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(12, FontWeight.w600, C.muted)),
                  Text(timeStr, style: nu(11, FontWeight.w600, C.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // User can delete; strictly no edit/update option
            Pressable(
              onTap: () {
                Buzz.medium();
                openDialog((ctx) => AppDialog(
                  title: 'Delete post?',
                  children: [
                    const Text('Are you sure you want to delete this post? This cannot be undone.'),
                  ],
                  actions: [
                    Btn('Delete', kind: Kind.dng, onTap: () {
                      store.deletePost(p.id);
                      toast('Post deleted');
                      return true;
                    }),
                    const Btn('Cancel'),
                  ],
                ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDE8E8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFFDC2626)),
                    const SizedBox(width: 4),
                    Text('Delete', style: nu(12, FontWeight.w700, const Color(0xFFDC2626))),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '“$l”',
                style: const TextStyle(
                  fontFamily: F.serif,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  height: 1.35,
                  color: Color(0xFF332920),
                ),
              ),
            ),
        ],
        if (words.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final w in words)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    w,
                    style: const TextStyle(
                      fontFamily: F.sans,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF26A21),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.favorite_rounded, size: 14, color: Color(0xFFEF4444)),
            const SizedBox(width: 4),
            Text('$likes', style: nu(12, FontWeight.w700, C.muted)),
            const SizedBox(width: 14),
            const Icon(Icons.share_rounded, size: 14, color: Color(0xFFF26A21)),
            const SizedBox(width: 4),
            Text('$shares', style: nu(12, FontWeight.w700, C.muted)),
          ],
        ),
      ],
    ),
  );
}

