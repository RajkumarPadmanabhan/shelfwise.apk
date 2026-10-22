import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'common.dart';
import 'dialogs.dart';
import 'fx.dart';

const _peerPalette = [
  Color(0xFFE0703F),
  Color(0xFFC08A2E),
  Color(0xFF6F8F6A),
  Color(0xFF8A6FB0),
  Color(0xFFD0607A),
  Color(0xFF4F8FA8),
];

/// Packages a selected book into a .shelfbook archive (book.json + cover.img + content.dat).
class ShelfBookPackage {
  static Future<File> export(Item book) async {
    final archive = Archive();

    // 1. Metadata
    final jsonBytes = utf8.encode(jsonEncode(book.toJson()));
    archive.addFile(ArchiveFile('book.json', jsonBytes.length, jsonBytes));

    // 2. Cover image
    if (book.cover != null) {
      final cFile = store.imageFile(book.cover!);
      if (cFile.existsSync()) {
        final cBytes = await cFile.readAsBytes();
        archive.addFile(ArchiveFile('cover.img', cBytes.length, cBytes));
      }
    }

    // 3. Attached PDF or EPUB copy
    if (book.file != null) {
      final bFile = store.bookFile(book.file!);
      if (bFile.existsSync()) {
        final fBytes = await bFile.readAsBytes();
        archive.addFile(ArchiveFile('content.dat', fBytes.length, fBytes));
      }
    }

    final zipBytes = ZipEncoder().encode(archive);
    final tempDir = await getTemporaryDirectory();
    final safeTitle = book.title.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_').trim();
    final outName = safeTitle.isEmpty ? 'shelfwise_book' : safeTitle;
    final file = File('${tempDir.path}/$outName.shelfbook');
    await file.writeAsBytes(zipBytes, flush: true);
    return file;
  }

  static Future<Item?> unpack(Uint8List zipBytes, {required String fromUser, bool permanent = false}) async {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      Item? book;
      Uint8List? coverBytes;
      Uint8List? contentBytes;

      for (final f in archive) {
        if (f.name == 'book.json') {
          final content = f.content as List<int>;
          final map = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
          book = Item.fromJson(map);
        } else if (f.name == 'cover.img') {
          coverBytes = Uint8List.fromList(f.content as List<int>);
        } else if (f.name == 'content.dat') {
          contentBytes = Uint8List.fromList(f.content as List<int>);
        }
      }

      if (book == null) return null;

      // Save unpacked cover
      if (coverBytes != null) {
        final coverName = '${newId()}.jpg';
        final coverFile = store.imageFile(coverName);
        await coverFile.writeAsBytes(coverBytes, flush: true);
        book.cover = coverName;
      }

      // Save unpacked book copy
      if (contentBytes != null && book.file != null) {
        final ext = book.file!.endsWith('.epub') ? 'epub' : 'pdf';
        final fileName = '${newId()}.$ext';
        final bFile = store.bookFile(fileName);
        await bFile.writeAsBytes(contentBytes, flush: true);
        book.file = fileName;
      }

      return store.receiveSharedBook(book, fromUser: fromUser, permanent: permanent);
    } catch (e) {
      debugPrint('Error unpacking .shelfbook package: $e');
      return null;
    }
  }
}

/// Discovered peer representation.
class PeerDevice {
  final String id;
  final String name;
  final String device;
  final String how; // 'network' or 'room'
  final String ip;
  String status;
  int? progress;

  PeerDevice({
    required this.id,
    required this.name,
    required this.device,
    required this.how,
    required this.ip,
    this.status = 'Tap to send',
    this.progress,
  });
}

/// Live peer-to-peer server listening on port 8942.
class LiveReceiverServer {
  static HttpServer? _server;
  static String? _localIp;
  static String currentRoom = '';

  static bool get isListening => _server != null;
  static String? get localIp => _localIp;

  static Future<String?> refreshIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            _localIp = addr.address;
            return _localIp;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> startServer({
    required BuildContext context,
    required void Function(Item book, String sender) onAccepted,
  }) async {
    if (_server != null) return true;
    try {
      await refreshIp();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8942);
      _server!.listen((HttpRequest request) async {
        if (request.method == 'GET' && request.uri.path == '/peer-info') {
          // Respond with peer identity
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'id': store.profile.handle.isNotEmpty ? store.profile.handle : 'reader',
              'name': store.profile.name.isNotEmpty ? store.profile.name : 'Reader',
              'device': 'Shelfwise · Android',
              'room': currentRoom,
              'ip': _localIp ?? '',
            }))
            ..close();
          return;
        }

        if (request.method == 'POST' && request.uri.path == '/send-book') {
          try {
            if (!store.settings.acceptShared) {
              request.response
                ..statusCode = HttpStatus.forbidden
                ..write(jsonEncode({'error': 'Recipient is not accepting shared books'}))
                ..close();
              return;
            }

            final sender = request.headers.value('x-sender') ?? 'Nearby Reader';
            final bodyBytes = await request.fold<List<int>>([], (prev, elem) => prev..addAll(elem));

            final archive = ZipDecoder().decodeBytes(bodyBytes);
            ArchiveFile? jsonFile;
            for (final f in archive) {
              if (f.name == 'book.json') {
                jsonFile = f;
                break;
              }
            }

            if (jsonFile == null) {
              request.response
                ..statusCode = HttpStatus.badRequest
                ..write(jsonEncode({'error': 'Invalid book package'}))
                ..close();
              return;
            }

            final map = jsonDecode(utf8.decode(jsonFile.content as List<int>)) as Map<String, dynamic>;
            final candidate = Item.fromJson(map);

            if (!context.mounted) {
              request.response
                ..statusCode = HttpStatus.serviceUnavailable
                ..close();
              return;
            }

            Sfx.play('pop');
            Buzz.medium();
            final accept = await confirm(
              'Incoming Book Share',
              '“${candidate.title}” by ${candidate.author}\n\n'
              'Sent from $sender. Accept and add this book to your “Shared books” shelf?',
              yes: 'Accept Book',
              no: 'Decline',
              kind: Kind.pri,
            );

            if (accept) {
              final received = await ShelfBookPackage.unpack(
                Uint8List.fromList(bodyBytes),
                fromUser: sender,
                permanent: true,
              );
              if (received != null) {
                onAccepted(received, sender);
                request.response
                  ..statusCode = HttpStatus.ok
                  ..write(jsonEncode({'status': 'accepted', 'title': received.title}))
                  ..close();
                return;
              }
            }

            request.response
              ..statusCode = HttpStatus.forbidden
              ..write(jsonEncode({'error': 'Declined by recipient'}))
              ..close();
          } catch (e) {
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..close();
          }
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });
      return true;
    } catch (e) {
      debugPrint('Failed to start LiveReceiverServer: $e');
      return false;
    }
  }

  static void stopServer() {
    _server?.close(force: true);
    _server = null;
  }
}

/// Opens the P2P Book Share modal (Send & Receive).
void openBookShareSheet(BuildContext context, {Item? book, int initialTab = 0}) {
  Buzz.tick();
  openDialog((ctx) => _BookShareDialog(book: book, initialTab: initialTab));
}

class _BookShareDialog extends StatefulWidget {
  final Item? book;
  final int initialTab;

  const _BookShareDialog({this.book, this.initialTab = 0});

  @override
  State<_BookShareDialog> createState() => _BookShareDialogState();
}

class _BookShareDialogState extends State<_BookShareDialog>
    with SingleTickerProviderStateMixin {
  Item? _selectedBook;
  late final TextEditingController _roomCtrl = TextEditingController();
  late final AnimationController _radarCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  final List<PeerDevice> _peers = [];
  bool _isExporting = false;
  bool _isScanning = false;
  String _room = '';

  @override
  void initState() {
    super.initState();
    _selectedBook = widget.book ?? (store.allBooks.isNotEmpty ? store.allBooks.first : null);
    _startLocalServerAndScan();
  }

  Future<void> _startLocalServerAndScan() async {
    await LiveReceiverServer.refreshIp();
    if (!mounted) return;

    await LiveReceiverServer.startServer(
      context: context,
      onAccepted: (book, sender) {
        if (!mounted) return;
        Buzz.medium();
        Sfx.play('fanfare');
        final size = MediaQuery.sizeOf(context);
        confetti(Offset(size.width / 2, size.height * .4), count: 40);
        _showReceivedBanner(book, sender);
      },
    );

    _scanLocalPeers();
  }

  void _showReceivedBanner(Item book, String sender) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2B1D10),
        duration: const Duration(seconds: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            Expanded(
              child: Text(
                '📚 $sender shared “${book.title}”. It’s on your Shared shelf.',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13.5),
              ),
            ),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                Navigator.of(context).pop();
                store.changed();
              },
              child: const Text('View', style: TextStyle(color: Color(0xFFF26A21), fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                for (final col in store.cols) {
                  col.items.removeWhere((i) => i.id == book.id);
                }
                store.changed();
                toast('Book removed from Shared shelf');
              },
              child: const Text('Undo', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanLocalPeers() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);

    final ip = LiveReceiverServer.localIp;
    if (ip == null || !ip.contains('.')) {
      setState(() => _isScanning = false);
      return;
    }

    final subnet = ip.substring(0, ip.lastIndexOf('.'));
    final currentHost = int.tryParse(ip.substring(ip.lastIndexOf('.') + 1)) ?? 0;

    // Fast targeted scan around current IP
    final candidates = <int>[];
    for (int d = 1; d <= 20; d++) {
      if (currentHost - d > 0) candidates.add(currentHost - d);
      if (currentHost + d < 255) candidates.add(currentHost + d);
    }

    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 300);

    for (final hostNum in candidates) {
      if (!mounted) break;
      final targetIp = '$subnet.$hostNum';
      try {
        final req = await client.getUrl(Uri.parse('http://$targetIp:8942/peer-info'));
        final resp = await req.close();
        if (resp.statusCode == HttpStatus.ok) {
          final body = await utf8.decodeStream(resp);
          final map = jsonDecode(body) as Map<String, dynamic>;
          final id = map['id'] as String? ?? targetIp;
          final name = map['name'] as String? ?? 'Reader';
          final device = map['device'] as String? ?? 'Shelfwise · Android';
          final peerRoom = map['room'] as String? ?? '';

          if (!_peers.any((p) => p.ip == targetIp)) {
            final how = (_room.isNotEmpty && peerRoom == _room) ? 'room' : 'network';
            _peers.add(PeerDevice(
              id: id,
              name: name,
              device: device,
              how: how,
              ip: targetIp,
            ));
            if (mounted) setState(() {});
          }
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _isScanning = false);
  }

  @override
  void dispose() {
    _roomCtrl.dispose();
    _radarCtrl.dispose();
    super.dispose();
  }

  /// Sends the selected book via Bluetooth & Quick Share.
  Future<void> _shareViaBluetooth() async {
    final b = _selectedBook;
    if (b == null) {
      toast('Select a book to share');
      return;
    }

    setState(() => _isExporting = true);
    Buzz.medium();
    Sfx.play('swoosh');

    try {
      final packageFile = await ShelfBookPackage.export(b);
      if (!mounted) return;

      final box = context.findRenderObject() as RenderBox?;
      toast('Scanning for nearest Bluetooth & Quick Share devices…');

      await SharePlus.instance.share(ShareParams(
        files: [XFile(packageFile.path, mimeType: 'application/octet-stream', name: '${b.title}.shelfbook')],
        subject: 'Shelfwise Book: ${b.title}',
        text: 'Sharing “${b.title}” by ${b.author} from Shelfwise. Open with Shelfwise or accept via Bluetooth in Shelfwise!',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));

      if (mounted) setState(() => _isExporting = false);
    } catch (e) {
      debugPrint('Bluetooth share error: $e');
      toast('Couldn’t package book for Bluetooth sharing');
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Sends to a discovered peer device.
  Future<void> _sendToPeer(PeerDevice peer) async {
    final b = _selectedBook;
    if (b == null) {
      toast('Select a book to send');
      return;
    }

    setState(() {
      peer.status = 'Connecting…';
      peer.progress = 10;
    });
    Buzz.medium();
    Sfx.play('swoosh');

    try {
      final packageFile = await ShelfBookPackage.export(b);
      final bytes = await packageFile.readAsBytes();

      setState(() {
        peer.status = 'Waiting for them…';
        peer.progress = 40;
      });

      final sender = store.profile.name.trim().isNotEmpty
          ? store.profile.name.trim()
          : (store.profile.first.isNotEmpty ? store.profile.first : 'Reader');

      final uri = Uri.parse('http://${peer.ip}:8942/send-book');
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);

      final req = await client.postUrl(uri);
      req.headers.set('x-sender', sender);
      req.headers.set('content-type', 'application/octet-stream');
      req.add(bytes);

      setState(() {
        peer.status = 'Sending cover… 100%';
        peer.progress = 85;
      });

      final resp = await req.close();
      final respBody = await utf8.decodeStream(resp);

      if (!mounted) return;

      if (resp.statusCode == HttpStatus.ok) {
        setState(() {
          peer.status = 'Sent ✓ Added to their Shared shelf';
          peer.progress = 100;
        });
        Buzz.medium();
        Sfx.play('fanfare');
        toast('🎉 “${b.title}” was added to ${peer.name}’s Shared shelf!');
      } else {
        setState(() {
          peer.status = 'They couldn’t take it';
          peer.progress = null;
        });
        Sfx.play('knock');
        toast('Transfer declined: $respBody');
      }
    } catch (e) {
      debugPrint('Peer send error: $e');
      if (mounted) {
        setState(() {
          peer.status = 'Couldn’t connect. Tap to retry';
          peer.progress = null;
        });
        toast('Could not reach ${peer.name} at ${peer.ip}:8942');
      }
    }
  }

  /// Lets receiver pick an incoming .shelfbook file transferred via Bluetooth or downloaded.
  Future<void> _pickAndAcceptBluetoothBook() async {
    Buzz.tick();
    final PlatformFile? f;
    try {
      f = await FilePicker.pickFile(
        type: FileType.any,
        dialogTitle: 'Select received .shelfbook from Bluetooth or Downloads',
      );
    } catch (_) {
      toast('Couldn’t open the file picker');
      return;
    }

    if (f == null) return;
    final bytes = f.path != null && File(f.path!).existsSync()
        ? await File(f.path!).readAsBytes()
        : await f.readAsBytes();

    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? jsonFile;
      for (final entry in archive) {
        if (entry.name == 'book.json') {
          jsonFile = entry;
          break;
        }
      }

      if (jsonFile == null) {
        Sfx.play('knock');
        toast('This is not a valid Shelfwise .shelfbook package');
        return;
      }

      final map = jsonDecode(utf8.decode(jsonFile.content as List<int>)) as Map<String, dynamic>;
      final candidate = Item.fromJson(map);

      final ok = await confirm(
        'Accept Bluetooth Book?',
        '“${candidate.title}” by ${candidate.author}\n\n'
        'Received from Bluetooth device. Accept and add this book to your “Shared books” shelf?',
        yes: 'Accept & Add',
        no: 'Decline',
        kind: Kind.pri,
      );

      if (!ok) return;

      final received = await ShelfBookPackage.unpack(bytes, fromUser: 'Bluetooth Peer', permanent: true);
      if (received != null && mounted) {
        Buzz.medium();
        Sfx.play('fanfare');
        final size = MediaQuery.sizeOf(context);
        confetti(Offset(size.width / 2, size.height * .4), count: 40);
        toast('🎉 “${received.title}” added to “Shared books” shelf!');
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error importing bluetooth book: $e');
      toast('Failed to read or accept this book file');
    }
  }

  void _joinRoom(String code) {
    final clean = code.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (clean.length != 5) {
      toast('Room code must be 5 letters (e.g. ABCDE)');
      return;
    }
    setState(() {
      _room = clean;
      LiveReceiverServer.currentRoom = clean;
    });
    Buzz.tick();
    toast('Joined room $_room');
    _scanLocalPeers();
  }

  void _createRoom() {
    final rnd = Random();
    final buffer = StringBuffer();
    for (int i = 0; i < 5; i++) {
      buffer.write(String.fromCharCode(65 + rnd.nextInt(26)));
    }
    _joinRoom(buffer.toString());
  }

  void _leaveRoom() {
    setState(() {
      _room = '';
      LiveReceiverServer.currentRoom = '';
    });
    Buzz.tick();
    toast('Left room');
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Share this book',
      maxWidth: 420,
      children: [
        // Header: Cover preview (tilted -4deg) + Title + Author
        if (_selectedBook != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.line),
            ),
            child: Row(
              children: [
                Transform.rotate(
                  angle: -0.07,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: BookCover(_selectedBook!, w: 44, h: 62, titleSize: 7, authorSize: 5),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedBook!.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: nu(14.5, FontWeight.w800, C.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedBook!.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nu(12, FontWeight.w600, C.muted),
                      ),
                      const SizedBox(height: 4),
                      Text('Only this selected book will be shared', style: nu(11, FontWeight.w700, C.brown)),
                    ],
                  ),
                ),
                if (store.allBooks.length > 1)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz_rounded),
                    tooltip: 'Change selected book',
                    onPressed: () => _showPickBookMenu(store.allBooks.toList()),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),

        // Bluetooth status banner from prototype
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F1DE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFB5E0AE)),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF2E9A3D),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x402E9A3D), blurRadius: 4, spreadRadius: 2),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bluetooth is on. You’re ready to share.',
                  style: nu(12.5, FontWeight.w700, const Color(0xFF245C2A)),
                ),
              ),
              Pressable(
                onTap: _isExporting ? null : _shareViaBluetooth,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _isExporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bluetooth_searching_rounded, size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Scan & Beam', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Nearby Readers Section
        Row(
          children: [
            Text('Nearby readers', style: nu(14, FontWeight.w800, C.ink)),
            const Spacer(),
            if (_isScanning)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              GestureDetector(
                onTap: _scanLocalPeers,
                child: Text('Refresh', style: nu(12, FontWeight.w700, C.brown)),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (_peers.isNotEmpty) ...[
          for (final (i, p) in _peers.indexed)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _peerPalette[i % _peerPalette.length],
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      p.name.isNotEmpty ? p.name.substring(0, 1).toUpperCase() : 'R',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: nu(13.5, FontWeight.w800, C.ink)),
                        Text(p.status,
                            style: nu(11.5, FontWeight.w600,
                                p.status.contains('✓') ? const Color(0xFF2E7D32) : C.muted)),
                        if (p.progress != null) ...[
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: p.progress! / 100.0,
                              minHeight: 4,
                              color: const Color(0xFFF26A21),
                              backgroundColor: C.field,
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          '${p.device} · ${p.how == 'room' ? 'In room $_room' : 'On your network'}',
                          style: nu(10.5, FontWeight.w600, C.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded, color: Color(0xFFB8692A)),
                    onPressed: () => _sendToPeer(p),
                    tooltip: 'Send to ${p.name}',
                  ),
                ],
              ),
            ),
        ] else ...[
          // Prototype pulsing radar view
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFDFBF7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.line),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: AnimatedBuilder(
                    animation: _radarCtrl,
                    builder: (context, _) {
                      final val = _radarCtrl.value;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 64 * val,
                            height: 64 * val,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFF26A21).withValues(alpha: (1.0 - val).clamp(0.0, 0.7)),
                                width: 2,
                              ),
                            ),
                          ),
                          Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFF26A21),
                              boxShadow: [
                                BoxShadow(color: Color(0x66F26A21), blurRadius: 6, spreadRadius: 2),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Looking for readers nearby…',
                  style: nu(13, FontWeight.w800, C.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  'Open Shelfwise on another device on the same Wi‑Fi, or share a 5-letter room code below.',
                  textAlign: TextAlign.center,
                  style: nu(11.5, FontWeight.w600, C.muted, 1.35),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),

        // Room code container
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1E3CD),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Not on the same Wi‑Fi?', style: nu(12.5, FontWeight.w800, C.ink)),
              const SizedBox(height: 8),
              if (_room.isNotEmpty)
                Row(
                  children: [
                    Text('In room ', style: nu(13, FontWeight.w700, C.ink)),
                    Text(_room, style: nu(15, FontWeight.w900, const Color(0xFFB8692A))),
                    const Spacer(),
                    Pressable(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _room));
                        toast('Room code copied');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Copy', style: nu(12, FontWeight.w800, C.ink)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Pressable(
                      onTap: _leaveRoom,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Leave', style: nu(12, FontWeight.w800, C.dangerInk)),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _roomCtrl,
                        maxLength: 5,
                        textCapitalization: TextCapitalization.characters,
                        textAlign: TextAlign.center,
                        style: nu(15, FontWeight.w900, C.ink),
                        decoration: InputDecoration(
                          hintText: 'ABCDE',
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: C.line),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Pressable(
                      onTap: () => _joinRoom(_roomCtrl.text),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF171717),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Join', style: nu(12.5, FontWeight.w800, Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Pressable(
                      onTap: _createRoom,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEDFC9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('New room', style: nu(12.5, FontWeight.w800, C.ink)),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Accept books shared with me
        Row(
          children: [
            Checkbox(
              value: store.settings.acceptShared,
              activeColor: const Color(0xFFF26A21),
              onChanged: (v) {
                setState(() => store.settings.acceptShared = v ?? true);
                store.changed();
              },
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => store.settings.acceptShared = !store.settings.acceptShared);
                  store.changed();
                },
                child: Text('Accept books shared with me', style: nu(13, FontWeight.w700, C.ink)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Import Received Bluetooth Book (.shelfbook)
        Pressable(
          onTap: _pickAndAcceptBluetoothBook,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF4EB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8D5C2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.file_download_outlined, color: Color(0xFFB8692A), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Import Received Bluetooth Book (.shelfbook)',
                    style: nu(12.5, FontWeight.w800, const Color(0xFFB8692A)),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFB8692A)),
              ],
            ),
          ),
        ),
      ],
      actions: const [
        Btn('Close', onTap: null),
      ],
    );
  }

  void _showPickBookMenu(List<Item> allBooks) {
    openDialog((ctx) => AppDialog(
          title: 'Select book to share',
          maxWidth: 360,
          children: [
            for (final b in allBooks)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: BookCover(b, w: 32, h: 44, titleSize: 6, authorSize: 5),
                ),
                title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(13.5, FontWeight.w800)),
                subtitle: Text(b.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(11.5, FontWeight.w600, C.muted)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedBook = b);
                },
              ),
          ],
          actions: const [Btn('Cancel')],
        ));
  }
}
