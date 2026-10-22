import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../data/posts_models.dart';
import '../data/store.dart';
import '../icons.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/common.dart';

class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  String _filter = 'all'; // 'all', 'saved', 'mine'
  final ScrollController _scrollCtrl = ScrollController();
  String? _newestPostId;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _openComposer() {
    Buzz.tick();
    showModalBottomSheet<Post?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ComposerSheet(),
    ).then((newPost) {
      if (newPost != null && mounted) {
        setState(() {
          _filter = 'all';
          _newestPostId = newPost.id;
        });
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 350),
          curve: ease,
        );
        toast('Posted. Your thoughts are live');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final allPosts = store.posts;
        final isGrid = store.postsView == 'grid';

        final filtered = allPosts.where((p) {
          if (_filter == 'saved') return store.isPostSaved(p.id);
          if (_filter == 'mine') return p.mine;
          return true;
        }).toList();

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: topPad + 18),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Transform.rotate(
                          angle: -3 * pi / 180,
                          alignment: Alignment.centerLeft,
                          child: const Text(
                            'What are you reading?',
                            style: TextStyle(
                              fontFamily: F.hand,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              color: Color(0xFFF26A21),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Posts',
                          style: TextStyle(
                            fontFamily: F.serif,
                            fontWeight: FontWeight.w800,
                            fontSize: 32,
                            letterSpacing: -0.4,
                            height: 1.05,
                            color: C.ink,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Toolbar row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
                    child: Row(
                      children: [
                        // Filter chips
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                _FilterChip(
                                  label: 'All',
                                  active: _filter == 'all',
                                  onTap: () => setState(() => _filter = 'all'),
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: 'Saved',
                                  active: _filter == 'saved',
                                  onTap: () => setState(() => _filter = 'saved'),
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: 'My posts',
                                  active: _filter == 'mine',
                                  onTap: () => setState(() => _filter = 'mine'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // List/Grid layout toggle
                        _ViewToggle(
                          isGrid: isGrid,
                          onChange: (grid) => store.setPostsView(grid ? 'grid' : 'list'),
                        ),
                      ],
                    ),
                  ),

                  // Feed list / grid
                  Expanded(
                    child: filtered.isEmpty
                        ? _buildEmptyState()
                        : isGrid
                            ? _buildGrid(filtered, bottomPad)
                            : _buildList(filtered, bottomPad),
                  ),
                ],
              ),

              // Floating "＋ Write a post" button
              Positioned(
                left: 0,
                right: 0,
                bottom: 96 + bottomPad, // Sits cleanly above bottom nav bar
                child: Center(
                  child: _WritePostFab(onTap: _openComposer),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final msg = _filter == 'saved'
        ? 'Nothing saved yet.\nTap the bookmark on a post.'
        : _filter == 'mine'
            ? 'You haven’t posted yet.\nTap “Write a post”.'
            : 'No posts yet.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Text(
          msg,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: F.hand,
            fontSize: 25,
            color: Color(0xFF9A8A74),
            height: 1.15,
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<Post> posts, double bottomPad) {
    return ListView.builder(
      controller: _scrollCtrl,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 2, 16, 160 + bottomPad),
      itemCount: posts.length,
      itemBuilder: (context, i) {
        final p = posts[i];
        final isNew = p.id == _newestPostId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PostCard(
            key: ValueKey(p.id),
            post: p,
            isGrid: false,
            animateDrop: isNew,
            onDeleted: () {
              if (mounted && _filter == 'mine') setState(() {});
            },
          ),
        );
      },
    );
  }

  Widget _buildGrid(List<Post> posts, double bottomPad) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth < 340 ? 1 : 2;
        return GridView.builder(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 2, 16, 160 + bottomPad),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: cols == 1 ? 2.2 : 0.88,
          ),
          itemCount: posts.length,
          itemBuilder: (context, i) {
            final p = posts[i];
            final isNew = p.id == _newestPostId;
            return _PostCard(
              key: ValueKey(p.id),
              post: p,
              isGrid: true,
              animateDrop: isNew,
              onDeleted: () {
                if (mounted && _filter == 'mine') setState(() {});
              },
            );
          },
        );
      },
    );
  }
}

// -------------------------------------------------------------
// FILTER CHIP
// -------------------------------------------------------------
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Buzz.tick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: active ? C.brown : C.chip,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: F.sans,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            color: active ? Colors.white : C.chipText,
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// VIEW TOGGLE (List / Grid)
// -------------------------------------------------------------
class _ViewToggle extends StatelessWidget {
  final bool isGrid;
  final ValueChanged<bool> onChange;

  const _ViewToggle({required this.isGrid, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: C.chip,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleItem(
            icon: Ic.list,
            selected: !isGrid,
            tooltip: 'List view',
            onTap: () {
              Buzz.tick();
              onChange(false);
            },
          ),
          _ToggleItem(
            icon: Ic.grid,
            selected: isGrid,
            tooltip: 'Grid view',
            onTap: () {
              Buzz.tick();
              onChange(true);
            },
          ),
        ],
      ),
    );
  }
}

class _ToggleItem extends StatelessWidget {
  final String icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  const _ToggleItem({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 34,
        height: 32,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x2E000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: SvgIcon(
          icon,
          size: 19,
          color: selected ? C.ink : const Color(0xFF6D5C4B),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// POST CARD
// -------------------------------------------------------------
class _PostCard extends StatefulWidget {
  final Post post;
  final bool isGrid;
  final bool animateDrop;
  final VoidCallback onDeleted;

  const _PostCard({
    super.key,
    required this.post,
    required this.isGrid,
    this.animateDrop = false,
    required this.onDeleted,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _slideAnim;

  // Pop scale triggers for like and save
  double _likeScale = 1.0;
  double _saveScale = 1.0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _scaleAnim = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
    _slideAnim = Tween<double>(begin: -14.0, end: 0.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );

    if (widget.animateDrop) {
      _animCtrl.forward();
    } else {
      _animCtrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _triggerPop(bool isLike) {
    setState(() {
      if (isLike) {
        _likeScale = 1.35;
      } else {
        _saveScale = 1.35;
      }
    });
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) {
        setState(() {
          if (isLike) {
            _likeScale = 1.0;
          } else {
            _saveScale = 1.0;
          }
        });
      }
    });
  }

  void _onLike() {
    Buzz.medium();
    Sfx.play('tap');
    _triggerPop(true);
    store.toggleLikePost(widget.post.id);
  }

  void _onSave() {
    Buzz.medium();
    Sfx.play('tap');
    _triggerPop(false);
    final isSavedNow = store.toggleSavePost(widget.post.id);
    toast(isSavedNow ? 'Saved to your list' : 'Removed from saved');
  }

  void _onShare() async {
    Buzz.tick();
    final p = widget.post;
    final text = '“${p.fullText}” — ${p.authorName} on ${p.bookTitle} by ${p.bookAuthor} · Readers';

    try {
      final res = await Share.share(text);
      if (res.status == ShareResultStatus.success) {
        store.incrementSharePost(p.id);
        toast('Shared');
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      store.incrementSharePost(p.id);
      toast('Copied. Paste it anywhere to share');
    }
  }

  void _onDelete() {
    Buzz.medium();
    store.deletePost(widget.post.id);
    widget.onDeleted();
    toast('Post deleted');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final isGrid = widget.isGrid;
    final isLiked = store.isPostLiked(p.id);
    final isSaved = store.isPostSaved(p.id);
    final likes = store.postLikes(p);
    final shares = store.postShares(p);

    final avatarBg = avatarColorFor(p.authorHandle);
    final initial = p.authorName.isNotEmpty ? p.authorName[0].toUpperCase() : 'R';
    final timeStr = formatTimeAgo(p.timestamp);

    Widget cardContent = Container(
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: C.line, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            offset: Offset(0, 2),
            blurRadius: 4,
          )
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        isGrid ? 10 : 14,
        isGrid ? 10 : 14,
        isGrid ? 10 : 14,
        isGrid ? 6 : 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: isGrid ? MainAxisSize.max : MainAxisSize.min,
        children: [
          // Header row
          Row(
            children: [
              // Circular avatar
              Container(
                width: isGrid ? 28 : 38,
                height: isGrid ? 28 : 38,
                decoration: BoxDecoration(
                  color: avatarBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: TextStyle(
                    fontFamily: F.sans,
                    fontWeight: FontWeight.w800,
                    fontSize: isGrid ? 13 : 16,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Name & handle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: TextStyle(
                          fontFamily: F.sans,
                          fontWeight: FontWeight.w700,
                          fontSize: isGrid ? 12.5 : 14.5,
                          color: C.ink,
                        ),
                        children: [
                          TextSpan(text: p.authorName),
                          if (p.mine)
                            const TextSpan(
                              text: ' (you)',
                              style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF7D6F62)),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '@${p.authorHandle} · $timeStr',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: F.sans,
                        fontSize: isGrid ? 10.5 : 12,
                        color: C.muted,
                      ),
                    ),
                  ],
                ),
              ),
              // Delete button if own post
              if (p.mine)
                GestureDetector(
                  onTap: _onDelete,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Delete',
                      style: TextStyle(
                        fontFamily: F.sans,
                        fontWeight: FontWeight.w700,
                        fontSize: isGrid ? 11 : 12,
                        color: C.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Content row / Grid view content
          if (isGrid) ...[
            // In Grid mode: Cover is hidden, book title shown in bold
            Text(
              p.bookTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: F.sans,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.25,
                color: C.ink,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: _buildPostText(p, isGrid: true),
              ),
            ),
          ] else ...[
            // In List mode: Cover on the left, post text on the right
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBookCover(p),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _buildPostText(p, isGrid: false),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),

          // Dashed divider line
          CustomPaint(
            size: const Size(double.infinity, 1),
            painter: DashedLinePainter(color: C.line),
          ),
          const SizedBox(height: 6),

          // Action bar
          Row(
            mainAxisAlignment: isGrid ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
            children: [
              // Like
              GestureDetector(
                onTap: _onLike,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      AnimatedScale(
                        scale: _likeScale,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutBack,
                        child: SvgIcon(
                          Ic.heart,
                          size: isGrid ? 18 : 20,
                          color: isLiked ? const Color(0xFFD1344A) : C.muted,
                          fill: isLiked ? const Color(0xFFD1344A) : null,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$likes',
                        style: TextStyle(
                          fontFamily: F.sans,
                          fontWeight: FontWeight.w700,
                          fontSize: isGrid ? 12 : 13,
                          color: isLiked ? const Color(0xFFD1344A) : C.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (!isGrid) const SizedBox(width: 12),

              // Save
              GestureDetector(
                onTap: _onSave,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      AnimatedScale(
                        scale: _saveScale,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutBack,
                        child: SvgIcon(
                          Ic.bookmark,
                          size: isGrid ? 18 : 20,
                          color: isSaved ? C.brown : C.muted,
                          fill: isSaved ? C.brown : null,
                        ),
                      ),
                      if (!isGrid) ...[
                        const SizedBox(width: 5),
                        Text(
                          isSaved ? 'Saved' : 'Save',
                          style: TextStyle(
                            fontFamily: F.sans,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: isSaved ? C.brown : C.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (!isGrid) const Spacer(),

              // Share
              GestureDetector(
                onTap: _onShare,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      SvgIcon(
                        Ic.share,
                        size: isGrid ? 18 : 20,
                        color: C.muted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$shares',
                        style: TextStyle(
                          fontFamily: F.sans,
                          fontWeight: FontWeight.w700,
                          fontSize: isGrid ? 12 : 13,
                          color: C.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (widget.animateDrop) {
      return AnimatedBuilder(
        animation: _animCtrl,
        builder: (context, child) {
          return Opacity(
            opacity: _animCtrl.value,
            child: Transform.translate(
              offset: Offset(0, _slideAnim.value),
              child: Transform.scale(
                scale: _scaleAnim.value,
                child: child,
              ),
            ),
          );
        },
        child: cardContent,
      );
    }

    return cardContent;
  }

  Widget _buildBookCover(Post p) {
    // Check if uploaded cover exists
    final imgName = p.bookCover;
    final file = imgName != null ? store.imageFile(imgName) : null;
    final hasImg = file != null && file.existsSync();

    if (hasImg) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 52,
          height: 74,
          decoration: BoxDecoration(
            color: const Color(0xFFE9DCC0),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Image.file(file, fit: BoxFit.cover),
        ),
      );
    }

    // Generated spine cover tile
    final pal = coverFor(p.bookTitle.isEmpty ? 'Untitled' : p.bookTitle);
    return Container(
      width: 46,
      height: 64,
      decoration: BoxDecoration(
        color: pal[0],
        borderRadius: BorderRadius.circular(4),
        border: pal.length > 2 ? Border(top: BorderSide(color: pal[2], width: 4)) : null,
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            p.bookTitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: F.sans,
              fontWeight: FontWeight.w700,
              fontSize: 8.5,
              height: 1.1,
              color: pal[1],
            ),
          ),
          if (p.bookAuthor.isNotEmpty) ...[
            const SizedBox(height: 3),
            Opacity(
              opacity: 0.85,
              child: Text(
                p.bookAuthor,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: F.sans,
                  fontWeight: FontWeight.w500,
                  fontSize: 7,
                  color: pal[1],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPostText(Post p, {required bool isGrid}) {
    final spans = <InlineSpan>[];

    for (int i = 0; i < p.items.length; i++) {
      final item = p.items[i];
      if (item.isLine) {
        spans.add(
          TextSpan(
            text: '${item.text} ',
            style: TextStyle(
              fontFamily: F.sans,
              fontSize: isGrid ? 13 : 15.5,
              height: isGrid ? 1.4 : 1.5,
              color: C.ink,
              fontWeight: FontWeight.w400,
            ),
          ),
        );
      } else {
        // Tag with orange highlighter underline effect
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0x38F26A21),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '#${item.text}',
                style: TextStyle(
                  fontFamily: F.sans,
                  fontWeight: FontWeight.w700,
                  fontSize: isGrid ? 12.5 : 15,
                  color: C.ink,
                ),
              ),
            ),
          ),
        );
      }
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }
}

// -------------------------------------------------------------
// FLOATING "＋ Write a post" BUTTON
// -------------------------------------------------------------
class _WritePostFab extends StatelessWidget {
  final VoidCallback onTap;

  const _WritePostFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: C.black,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              offset: Offset(0, 4),
              blurRadius: 12,
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '＋ ',
              style: TextStyle(
                fontFamily: F.sans,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Color(0xFFF26A21),
              ),
            ),
            const Text(
              'Write a post',
              style: TextStyle(
                fontFamily: F.sans,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// COMPOSER BOTTOM SHEET
// -------------------------------------------------------------
class _ComposerSheet extends StatefulWidget {
  const _ComposerSheet();

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  Item? _selectedBook;
  final List<PostItem> _selectedPieces = [];
  String _activeTab = 'l'; // 'l' = Lines, 'w' = Words

  bool _searchBooksOpen = false;
  final TextEditingController _bookSearchCtrl = TextEditingController();

  bool _searchWordsOpen = false;
  final TextEditingController _wordSearchCtrl = TextEditingController();

  @override
  void dispose() {
    _bookSearchCtrl.dispose();
    _wordSearchCtrl.dispose();
    super.dispose();
  }

  void _togglePiece(PostItem item) {
    Buzz.tick();
    setState(() {
      final index = _selectedPieces.indexWhere((p) => p.kind == item.kind && p.text == item.text);
      if (index >= 0) {
        _selectedPieces.removeAt(index);
      } else if (_selectedPieces.length < 4) {
        _selectedPieces.add(item);
      }
    });
  }

  void _removePieceAt(int i) {
    Buzz.tick();
    setState(() {
      _selectedPieces.removeAt(i);
    });
  }

  void _onPost() {
    if (_selectedBook == null || _selectedPieces.isEmpty) return;
    Buzz.medium();
    final newPost = store.addPost(
      bookTitle: _selectedBook!.title,
      bookAuthor: _selectedBook!.author,
      bookCover: _selectedBook!.cover,
      items: List.of(_selectedPieces),
    );
    Navigator.of(context).pop(newPost);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // Get shelf books deduplicated
    final shelfBooks = <Item>[];
    final seen = <String>{};
    for (final b in store.allBooks) {
      final key = '${b.title.trim().toLowerCase()}|${b.author.trim().toLowerCase()}';
      if (b.title.trim().isNotEmpty && seen.add(key)) {
        shelfBooks.add(b);
      }
    }

    // Filter shelf books by search
    final bq = _bookSearchCtrl.text.trim().toLowerCase();
    final filteredBooks = bq.isEmpty
        ? shelfBooks
        : shelfBooks.where((b) => '${b.title} ${b.author}'.toLowerCase().contains(bq)).toList();

    final canPost = _selectedBook != null && _selectedPieces.isNotEmpty;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x47000000),
            blurRadius: 30,
            offset: Offset(0, -10),
          )
        ],
      ),
      padding: EdgeInsets.fromLTRB(18, 8, 18, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grab handle
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: C.inputLine,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Title & Close
          Row(
            children: [
              const Expanded(
                child: Text(
                  'New post',
                  style: TextStyle(
                    fontFamily: F.hand,
                    fontWeight: FontWeight.w700,
                    fontSize: 27,
                    color: Color(0xFF171717),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: C.chip,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('✕', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Step 1 Header
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '1 · Which book?',
                          style: TextStyle(
                            fontFamily: F.hand,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: Color(0xFF171717),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _searchBooksOpen = !_searchBooksOpen),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _searchBooksOpen ? C.brown : C.chip,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: SvgIcon(
                              Ic.search,
                              size: 19,
                              color: _searchBooksOpen ? Colors.white : const Color(0xFF6D5C4B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Search books input if open
                  if (_searchBooksOpen) ...[
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: C.inputLine, width: 1.5),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SvgIcon(Ic.search, size: 18, color: C.muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _bookSearchCtrl,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(fontFamily: F.sans, fontSize: 14, color: C.ink),
                              decoration: const InputDecoration(
                                hintText: 'Search title or author',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          if (_bookSearchCtrl.text.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() => _bookSearchCtrl.clear()),
                              child: const Icon(Icons.clear, size: 18, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                  ],

                  // Books horizontal list
                  if (shelfBooks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Add a book to your shelf first, then come back to post about it.',
                        style: TextStyle(fontFamily: F.sans, fontSize: 13, color: Color(0xFF7D6F62)),
                      ),
                    )
                  else if (filteredBooks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '“${_bookSearchCtrl.text.trim()}” not found in your shelf.',
                        style: const TextStyle(fontFamily: F.sans, fontSize: 13, color: Color(0xFF7D6F62)),
                      ),
                    )
                  else
                    SizedBox(
                      height: 84,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: filteredBooks.length,
                        itemBuilder: (context, i) {
                          final b = filteredBooks[i];
                          final isSelected = _selectedBook == b;
                          return Padding(
                            padding: const EdgeInsets.only(right: 10, top: 6, bottom: 6),
                            child: _BookPickerTile(
                              book: b,
                              selected: isSelected,
                              onTap: () {
                                Buzz.tick();
                                setState(() => _selectedBook = b);
                              },
                            ),
                          );
                        },
                      ),
                    ),

                  // Selected book title & author label
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Text(
                      _selectedBook != null
                          ? '${_selectedBook!.title}${_selectedBook!.author.isNotEmpty ? ' · ${_selectedBook!.author}' : ''}'
                          : (shelfBooks.isNotEmpty ? 'Pick a book from your shelf (${shelfBooks.length})' : 'Pick a book'),
                      style: TextStyle(
                        fontFamily: F.sans,
                        fontSize: 13,
                        color: _selectedBook != null ? C.brown : C.muted,
                        fontWeight: _selectedBook != null ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),

                  // Step 2 Header
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      '2 · Your post',
                      style: TextStyle(
                        fontFamily: F.hand,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: Color(0xFF171717),
                      ),
                    ),
                  ),

                  // Post live preview box + Post button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Preview box
                      Expanded(
                        child: CustomPaint(
                          painter: DashedBoxPainter(color: C.inputLine, radius: 16),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 70),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: _selectedPieces.isEmpty
                                ? const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Pick a few lines or words above…',
                                      style: TextStyle(
                                        fontFamily: F.hand,
                                        fontSize: 20,
                                        color: Color(0xFFA99A85),
                                      ),
                                    ),
                                  )
                                : Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (int i = 0; i < _selectedPieces.length; i++)
                                        _TokenChip(
                                          item: _selectedPieces[i],
                                          onRemove: () => _removePieceAt(i),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Post button
                      Opacity(
                        opacity: canPost ? 1.0 : 0.35,
                        child: GestureDetector(
                          onTap: canPost ? _onPost : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            decoration: BoxDecoration(
                              color: C.black,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              children: const [
                                Text(
                                  'Post ',
                                  style: TextStyle(
                                    fontFamily: F.sans,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '→',
                                  style: TextStyle(
                                    fontFamily: F.sans,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: Color(0xFFF26A21),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Counter row
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Tap a piece to remove it',
                          style: TextStyle(fontFamily: F.sans, fontSize: 12, color: C.muted),
                        ),
                        Text(
                          '${_selectedPieces.length} / 4',
                          style: TextStyle(fontFamily: F.sans, fontWeight: FontWeight.bold, fontSize: 12, color: C.muted),
                        ),
                      ],
                    ),
                  ),

                  // Step 3 Header
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '3 · Pick your words',
                          style: TextStyle(
                            fontFamily: F.hand,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: Color(0xFF171717),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _searchWordsOpen = !_searchWordsOpen),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _searchWordsOpen ? C.brown : C.chip,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: SvgIcon(
                              Ic.search,
                              size: 19,
                              color: _searchWordsOpen ? Colors.white : const Color(0xFF6D5C4B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Search words input
                  if (_searchWordsOpen) ...[
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: C.inputLine, width: 1.5),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SvgIcon(Ic.search, size: 18, color: C.muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _wordSearchCtrl,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(fontFamily: F.sans, fontSize: 14, color: C.ink),
                              decoration: const InputDecoration(
                                hintText: 'Search lines or words',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          if (_wordSearchCtrl.text.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() => _wordSearchCtrl.clear()),
                              child: const Icon(Icons.clear, size: 18, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                  ],

                  // Tab segmented control (Lines vs Words)
                  if (_wordSearchCtrl.text.isEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: C.chip,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.all(3),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ComposerTabItem(
                            label: 'Lines',
                            selected: _activeTab == 'l',
                            onTap: () {
                              Buzz.tick();
                              setState(() => _activeTab = 'l');
                            },
                          ),
                          _ComposerTabItem(
                            label: 'Words',
                            selected: _activeTab == 'w',
                            onTap: () {
                              Buzz.tick();
                              setState(() => _activeTab = 'w');
                            },
                          ),
                        ],
                      ),
                    ),

                  // Options pills area
                  _buildOptionsArea(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsArea() {
    final query = _wordSearchCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'^#'), '');
    final full = _selectedPieces.length >= 4;

    if (query.isNotEmpty) {
      final matchLines = <String>[];
      final matchWords = <String>[];
      for (final l in postPresetLines) {
        if (l.toLowerCase().contains(query)) matchLines.add(l);
      }
      for (final w in postPresetWords) {
        if (w.toLowerCase().contains(query)) matchWords.add(w);
      }

      if (matchLines.isEmpty && matchWords.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'No lines or words match “${_wordSearchCtrl.text.trim()}”.',
            style: TextStyle(fontFamily: F.sans, fontSize: 13, color: C.muted),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (matchLines.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                'Lines (${matchLines.length})',
                style: const TextStyle(fontFamily: F.hand, fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFB8692A)),
              ),
            ),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final l in matchLines)
                  _PresetPill(
                    item: PostItem(kind: 'l', text: l),
                    selected: _selectedPieces.any((p) => p.kind == 'l' && p.text == l),
                    disabled: full && !_selectedPieces.any((p) => p.kind == 'l' && p.text == l),
                    onTap: () => _togglePiece(PostItem(kind: 'l', text: l)),
                  ),
              ],
            ),
          ],
          if (matchWords.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Text(
                'Words (${matchWords.length})',
                style: const TextStyle(fontFamily: F.hand, fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFB8692A)),
              ),
            ),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final w in matchWords)
                  _PresetPill(
                    item: PostItem(kind: 'w', text: w),
                    selected: _selectedPieces.any((p) => p.kind == 'w' && p.text == w),
                    disabled: full && !_selectedPieces.any((p) => p.kind == 'w' && p.text == w),
                    onTap: () => _togglePiece(PostItem(kind: 'w', text: w)),
                  ),
              ],
            ),
          ],
        ],
      );
    }

    final list = _activeTab == 'l' ? postPresetLines : postPresetWords;
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final text in list)
              _PresetPill(
                item: PostItem(kind: _activeTab, text: text),
                selected: _selectedPieces.any((p) => p.kind == _activeTab && p.text == text),
                disabled: full && !_selectedPieces.any((p) => p.kind == _activeTab && p.text == text),
                onTap: () => _togglePiece(PostItem(kind: _activeTab, text: text)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ComposerTabItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ComposerTabItem({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x2E000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: F.sans,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? C.ink : const Color(0xFF6D5C4B),
          ),
        ),
      ),
    );
  }
}

class _PresetPill extends StatelessWidget {
  final PostItem item;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _PresetPill({
    required this.item,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? C.brown : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? C.brown : C.inputLine,
              width: 1.5,
            ),
          ),
          child: Text(
            item.isWord ? '#${item.text}' : item.text,
            style: TextStyle(
              fontFamily: F.sans,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
              color: selected ? Colors.white : C.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _TokenChip extends StatelessWidget {
  final PostItem item;
  final VoidCallback onRemove;

  const _TokenChip({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRemove,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: item.isWord ? const Color(0x40F26A21) : C.chip,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.isWord ? '#${item.text}' : item.text,
              style: TextStyle(
                fontFamily: F.sans,
                fontWeight: item.isWord ? FontWeight.w800 : FontWeight.w600,
                fontSize: 14,
                color: C.ink,
              ),
            ),
            const SizedBox(width: 4),
            const Text('✕', style: TextStyle(fontSize: 10, color: Color(0x8A000000))),
          ],
        ),
      ),
    );
  }
}

class _BookPickerTile extends StatelessWidget {
  final Item book;
  final bool selected;
  final VoidCallback onTap;

  const _BookPickerTile({
    required this.book,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final file = book.cover != null ? store.imageFile(book.cover!) : null;
    final hasImg = file != null && file.existsSync();
    final pal = coverFor(book.title.isEmpty ? 'Untitled' : book.title);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.translationValues(0, selected ? -5 : 0, 0),
        width: 52,
        height: 72,
        decoration: BoxDecoration(
          color: pal[0],
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? const Color(0xFFF26A21) : Colors.transparent,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected ? const Color(0x55F26A21) : const Color(0x38000000),
              blurRadius: selected ? 8 : 4,
              offset: Offset(0, selected ? 2 : 1),
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: hasImg
            ? Image.file(file, fit: BoxFit.cover)
            : Container(
                padding: const EdgeInsets.all(4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: pal.length > 2 ? Border(top: BorderSide(color: pal[2], width: 4)) : null,
                ),
                child: Text(
                  book.title,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: F.sans,
                    fontWeight: FontWeight.w700,
                    fontSize: 8.5,
                    height: 1.1,
                    color: pal[1],
                  ),
                ),
              ),
      ),
    );
  }
}

// -------------------------------------------------------------
// CUSTOM PAINTERS: Dashed Line & Dashed Box
// -------------------------------------------------------------
class DashedLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;

  const DashedLinePainter({
    required this.color,
    this.dashWidth = 4,
    this.dashSpace = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(min(startX + dashWidth, size.width), 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant DashedLinePainter oldDelegate) => oldDelegate.color != color;
}

class DashedBoxPainter extends CustomPainter {
  final Color color;
  final double radius;

  const DashedBoxPainter({required this.color, this.radius = 16});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final extract = metric.extractPath(distance, distance + 5);
        canvas.drawPath(extract, paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBoxPainter oldDelegate) => oldDelegate.color != color;
}
