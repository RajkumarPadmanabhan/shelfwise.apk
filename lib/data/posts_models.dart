import 'dart:math';
import 'package:flutter/material.dart';

class PostItem {
  final String kind; // 'l' = line, 'w' = word
  final String text;

  const PostItem({required this.kind, required this.text});

  bool get isWord => kind == 'w';
  bool get isLine => kind == 'l';

  Map<String, dynamic> toJson() => {'k': kind, 't': text};

  factory PostItem.fromJson(Map<String, dynamic> j) => PostItem(
        kind: (j['k'] ?? 'l') as String,
        text: (j['t'] ?? '') as String,
      );
}

class Post {
  final String id;
  final bool mine;
  final String authorName;
  final String authorHandle;
  final String bookTitle;
  final String bookAuthor;
  final String? bookCover;
  final int timestamp;
  int likeCount;
  int shareCount;
  final List<PostItem> items;

  Post({
    required this.id,
    this.mine = false,
    required this.authorName,
    required this.authorHandle,
    required this.bookTitle,
    required this.bookAuthor,
    this.bookCover,
    required this.timestamp,
    this.likeCount = 0,
    this.shareCount = 0,
    required this.items,
  });

  String get fullText {
    final lines = <String>[];
    final words = <String>[];
    for (final item in items) {
      if (item.isWord) {
        words.add('#${item.text.replaceAll(RegExp(r'\s+'), '')}');
      } else {
        lines.add(item.text);
      }
    }
    return (lines + words).join(' ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mine': mine,
        'n': authorName,
        'h': authorHandle,
        'bt': bookTitle,
        'ba': bookAuthor,
        if (bookCover != null) 'bc': bookCover,
        'ts': timestamp,
        'l': likeCount,
        'sh': shareCount,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: (j['id'] ?? '') as String,
        mine: j['mine'] == true,
        authorName: (j['n'] ?? '') as String,
        authorHandle: (j['h'] ?? '') as String,
        bookTitle: (j['bt'] ?? '') as String,
        bookAuthor: (j['ba'] ?? '') as String,
        bookCover: j['bc'] as String?,
        timestamp: (j['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        likeCount: (j['l'] as num?)?.toInt() ?? 0,
        shareCount: (j['sh'] as num?)?.toInt() ?? 0,
        items: ((j['items'] ?? const []) as List)
            .map((e) => PostItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

const avatarPalette = <Color>[
  Color(0xFFE0703F),
  Color(0xFFC08A2E),
  Color(0xFF6F8F6A),
  Color(0xFF8A6FB0),
  Color(0xFFD0607A),
  Color(0xFF4F8FA8),
];

int handleHash(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7FFFFFFF;
  }
  return h;
}

Color avatarColorFor(String handle) {
  return avatarPalette[handleHash(handle) % avatarPalette.length];
}

String formatTimeAgo(int timestamp) {
  final diff = DateTime.now().millisecondsSinceEpoch - timestamp;
  if (diff < 45000) return 'now';
  if (diff < 3600000) return '${max(1, (diff / 60000).round())}m';
  if (diff < 86400000) return '${(diff / 3600000).round()}h';
  return '${(diff / 86400000).round()}d';
}

const postPresetLines = <String>[
  "Couldn’t put it down.",
  "That ending broke me.",
  "Read it in one sitting.",
  "Slow start, but so worth it.",
  "The writing is gorgeous.",
  "I cried on the train.",
  "An instant favourite.",
  "The perfect cosy read.",
  "A plot twist I never saw coming!",
  "Already planning a reread.",
  "Not for me, but I see why people love it.",
  "Adding it to my comfort shelf.",
  "Highly recommend!",
  "Needed this book today.",
  "Finished it at 3 a.m. and regret nothing.",
  "The characters felt like old friends.",
  "I want to live inside this world.",
  "A quiet book that hit me hard.",
  "The first chapter hooked me instantly.",
  "I missed my stop because of this book.",
  "Beautifully sad, in the best way.",
  "Made me laugh out loud in public.",
  "That twist at the end. Wow.",
  "Still thinking about it days later.",
  "It gave me goosebumps.",
  "The perfect book for a rainy day.",
  "A warm hug in book form.",
  "I underlined half the pages.",
  "The best book I’ve read this year.",
  "Dense, but so rewarding.",
  "The ending felt earned.",
  "I wasn’t ready for those last pages.",
  "A slow burn that pays off.",
  "Pure comfort reading.",
  "The world-building is incredible.",
  "I fell in love with every character.",
  "Read it in a single weekend.",
  "A book that changed how I think.",
  "Heartbreaking and hopeful at once.",
  "The dialogue is so sharp.",
  "I need the sequel right now.",
  "I want to hand this to everyone I know.",
  "Put my phone down for this one.",
  "Tissues required.",
  "Confusing at first, then it clicks.",
  "Perfect for a long flight.",
  "The prose is pure music.",
  "I’m obsessed. Send help.",
  "A gentle, thoughtful read.",
  "Dark, twisty and impossible to guess.",
  "This one deserves the hype.",
  "Didn’t love it, but I’m glad I read it.",
  "Reading it again tonight.",
  "The kind of book you savour slowly.",
  "It took me by surprise in the best way.",
  "A masterclass in tension.",
  "Book hangover is real.",
  "I laughed, I cried, I reread.",
  "Perfect with a cup of tea.",
  "Every shelf needs a copy.",
  "Couldn’t stop quoting it.",
  "Strong start, even stronger finish.",
  "A story that stays with you.",
  "It reminded me why I love reading.",
];

const postPresetWords = <String>[
  "cozy",
  "gripping",
  "heartbreaking",
  "hopeful",
  "dark",
  "funny",
  "slow-burn",
  "unputdownable",
  "beautiful",
  "thoughtful",
  "haunting",
  "magical",
  "twisty",
  "wholesome",
  "epic",
  "emotional",
  "romantic",
  "witty",
  "lyrical",
  "atmospheric",
  "fast-paced",
  "immersive",
  "moving",
  "clever",
  "bittersweet",
  "eerie",
  "uplifting",
  "tense",
  "dreamy",
  "gritty",
  "charming",
  "raw",
  "poetic",
  "suspenseful",
  "inspiring",
  "nostalgic",
  "quirky",
  "sweeping",
  "intimate",
  "chilling",
  "playful",
  "profound",
  "addictive",
  "cinematic",
  "tender",
  "brooding",
  "whimsical",
  "sharp",
  "layered",
  "comforting",
  "devastating",
  "luminous",
  "bold",
  "feel-good",
  "mind-bending",
  "relatable",
  "unforgettable",
  "spooky",
  "adventurous",
  "lush",
  "powerful",
  "heartwarming",
  "rich",
  "tearjerker",
];

List<Post> createSeedPosts() {
  return const <Post>[];
}

