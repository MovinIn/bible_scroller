class Reel {
  const Reel({
    required this.id,
    required this.reference,
    required this.book,
    required this.chapter,
    required this.startVerse,
    required this.endVerse,
    required this.slug,
    required this.imageUrl,
    required this.iqBookId,
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
  });

  final int id;
  final String reference;
  final String book;
  final int chapter;
  final int startVerse;
  final int endVerse;
  final String slug;
  final String imageUrl;
  final String iqBookId;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;

  factory Reel.fromJson(Map<String, dynamic> json) {
    return Reel(
      id: json['id'] as int,
      reference: json['reference'] as String,
      book: json['book'] as String,
      chapter: json['chapter'] as int,
      startVerse: json['start_verse'] as int,
      endVerse: json['end_verse'] as int,
      slug: json['slug'] as String,
      imageUrl: json['image_url'] as String,
      iqBookId: json['iq_book_id'] as String,
      likeCount: json['like_count'] as int,
      commentCount: json['comment_count'] as int,
      likedByMe: json['liked_by_me'] as bool,
    );
  }

  Reel copyWith({
    int? likeCount,
    int? commentCount,
    bool? likedByMe,
  }) {
    return Reel(
      id: id,
      reference: reference,
      book: book,
      chapter: chapter,
      startVerse: startVerse,
      endVerse: endVerse,
      slug: slug,
      imageUrl: imageUrl,
      iqBookId: iqBookId,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      likedByMe: likedByMe ?? this.likedByMe,
    );
  }
}

class ReelFeed {
  const ReelFeed({
    required this.items,
    required this.nextCursor,
    this.prevCursor,
  });

  final List<Reel> items;
  final int? nextCursor;
  final int? prevCursor;

  factory ReelFeed.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>)
        .map((item) => Reel.fromJson(item as Map<String, dynamic>))
        .toList();
    return ReelFeed(
      items: items,
      nextCursor: json['next_cursor'] as int?,
      prevCursor: json['prev_cursor'] as int?,
    );
  }
}

class VerseSection {
  const VerseSection({
    required this.id,
    required this.startVerse,
    required this.endVerse,
    required this.reference,
  });

  final int id;
  final int startVerse;
  final int endVerse;
  final String reference;

  /// Display label for picker grids: `16` or `1–4`.
  String get label =>
      startVerse == endVerse ? '$startVerse' : '$startVerse–$endVerse';

  factory VerseSection.fromJson(Map<String, dynamic> json) {
    return VerseSection(
      id: json['id'] as int,
      startVerse: json['start_verse'] as int,
      endVerse: json['end_verse'] as int,
      reference: json['reference'] as String,
    );
  }
}

class Comment {
  const Comment({
    required this.id,
    required this.reelId,
    required this.body,
    required this.likeCount,
    required this.likedByMe,
    required this.authorName,
    required this.createdAt,
    this.parentId,
  });

  final int id;
  final int reelId;
  final int? parentId;
  final String body;
  final int likeCount;
  final bool likedByMe;
  final String authorName;
  final DateTime createdAt;

  factory Comment.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>;
    return Comment(
      id: json['id'] as int,
      reelId: json['reel_id'] as int,
      parentId: json['parent_id'] as int?,
      body: json['body'] as String,
      likeCount: json['like_count'] as int,
      likedByMe: json['liked_by_me'] as bool,
      authorName: author['display_name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Comment copyWith({int? likeCount, bool? likedByMe}) {
    return Comment(
      id: id,
      reelId: reelId,
      parentId: parentId,
      body: body,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      authorName: authorName,
      createdAt: createdAt,
    );
  }
}

class BibleVersion {
  const BibleVersion({required this.versionId, required this.name});

  final String versionId;
  final String name;

  factory BibleVersion.fromJson(Map<String, dynamic> json) {
    return BibleVersion(
      versionId: json['version_id'] as String,
      name: json['name'] as String,
    );
  }
}

class BibleVerse {
  const BibleVerse({
    required this.reference,
    required this.versionId,
    required this.text,
  });

  final String reference;
  final String versionId;
  final String text;

  factory BibleVerse.fromJson(Map<String, dynamic> json) {
    return BibleVerse(
      reference: json['reference'] as String,
      versionId: json['version_id'] as String,
      text: json['text'] as String,
    );
  }
}

class WordGroup {
  const WordGroup({
    required this.phrase,
    required this.strongs,
    this.lemma = '',
    this.definition = '',
  });

  final String phrase;
  final String strongs;
  final String lemma;
  final String definition;

  factory WordGroup.fromJson(Map<String, dynamic> json) {
    return WordGroup(
      phrase: json['phrase'] as String,
      strongs: json['strongs'] as String,
      lemma: (json['lemma'] as String?) ?? '',
      definition: (json['definition'] as String?) ?? '',
    );
  }
}

class WordStudyVerse {
  const WordStudyVerse({
    required this.verse,
    required this.groups,
  });

  final int verse;
  final List<WordGroup> groups;

  factory WordStudyVerse.fromJson(Map<String, dynamic> json) {
    final raw = json['groups'];
    final groups = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(WordGroup.fromJson)
            .toList()
        : const <WordGroup>[];
    return WordStudyVerse(
      verse: json['verse'] as int,
      groups: groups,
    );
  }
}

class WordStudy {
  const WordStudy({
    required this.reference,
    required this.versionId,
    required this.verses,
  });

  final String reference;
  final String versionId;
  final List<WordStudyVerse> verses;

  List<WordGroup> get allGroups => [
        for (final verse in verses) ...verse.groups,
      ];

  factory WordStudy.fromJson(Map<String, dynamic> json) {
    final raw = json['verses'];
    final verses = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(WordStudyVerse.fromJson)
            .toList()
        : const <WordStudyVerse>[];
    return WordStudy(
      reference: json['reference'] as String,
      versionId: json['version_id'] as String,
      verses: verses,
    );
  }
}

class BibleAudioVerseTiming {
  const BibleAudioVerseTiming({
    required this.verse,
    required this.startMs,
    required this.endMs,
  });

  final int verse;
  final int startMs;
  final int endMs;

  factory BibleAudioVerseTiming.fromJson(Map<String, dynamic> json) {
    return BibleAudioVerseTiming(
      verse: json['verse'] as int,
      startMs: json['start_ms'] as int,
      endMs: json['end_ms'] as int,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BibleAudioVerseTiming &&
        other.verse == verse &&
        other.startMs == startMs &&
        other.endMs == endMs;
  }

  @override
  int get hashCode => Object.hash(verse, startMs, endMs);
}

class BibleAudio {
  const BibleAudio({
    required this.reference,
    required this.versionId,
    required this.audioUrl,
    this.startVerse = 1,
    this.endVerse = 1,
    this.verses = const [],
  });

  final String reference;
  final String versionId;
  final String audioUrl;
  final int startVerse;
  final int endVerse;
  final List<BibleAudioVerseTiming> verses;

  factory BibleAudio.fromJson(Map<String, dynamic> json) {
    final rawVerses = json['verses'];
    final verses = rawVerses is List
        ? rawVerses
            .whereType<Map<String, dynamic>>()
            .map(BibleAudioVerseTiming.fromJson)
            .toList()
        : const <BibleAudioVerseTiming>[];
    return BibleAudio(
      reference: json['reference'] as String,
      versionId: json['version_id'] as String,
      audioUrl: json['audio_url'] as String,
      startVerse: (json['start_verse'] as int?) ?? 1,
      endVerse: (json['end_verse'] as int?) ?? 1,
      verses: verses,
    );
  }
}

class LikeStatus {
  const LikeStatus({required this.liked, required this.likeCount});

  final bool liked;
  final int likeCount;

  factory LikeStatus.fromJson(Map<String, dynamic> json) {
    return LikeStatus(
      liked: json['liked'] as bool,
      likeCount: json['like_count'] as int,
    );
  }
}
