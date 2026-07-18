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

class BibleAudio {
  const BibleAudio({
    required this.reference,
    required this.versionId,
    required this.audioUrl,
  });

  final String reference;
  final String versionId;
  final String audioUrl;

  factory BibleAudio.fromJson(Map<String, dynamic> json) {
    return BibleAudio(
      reference: json['reference'] as String,
      versionId: json['version_id'] as String,
      audioUrl: json['audio_url'] as String,
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
