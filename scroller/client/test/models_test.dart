import 'package:flutter_test/flutter_test.dart';

import 'package:bible_scroller/models/models.dart';

void main() {
  test('parses reel json when feed item is returned from api', () {
    final reel = Reel.fromJson({
      'id': 1,
      'reference': 'John 3:16',
      'book': 'John',
      'chapter': 3,
      'start_verse': 16,
      'end_verse': 16,
      'slug': 'John_3_16-16',
      'image_url': 'https://example.com/image.png',
      'iq_book_id': '43',
      'like_count': 2,
      'comment_count': 1,
      'liked_by_me': true,
    });

    expect(reel.reference, 'John 3:16');
    expect(reel.likeCount, 2);
    expect(reel.likedByMe, isTrue);
  });

  test('parses comment json when comment is returned from api', () {
    final comment = Comment.fromJson({
      'id': 9,
      'reel_id': 1,
      'parent_id': 4,
      'body': 'Amen',
      'like_count': 3,
      'liked_by_me': false,
      'created_at': '2026-07-12T12:00:00Z',
      'author': {'id': 'abc', 'display_name': 'Reader-1234'},
    });

    expect(comment.body, 'Amen');
    expect(comment.parentId, 4);
    expect(comment.authorName, 'Reader-1234');
    expect(comment.likeCount, 3);
  });
}
