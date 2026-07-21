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

  test('parses verse section json when section is returned from api', () {
    final section = VerseSection.fromJson({
      'id': 42,
      'start_verse': 1,
      'end_verse': 4,
      'reference': 'John 3:1-4',
    });

    expect(section.id, 42);
    expect(section.startVerse, 1);
    expect(section.endVerse, 4);
    expect(section.reference, 'John 3:1-4');
  });

  test('uses range label when section spans multiple verses', () {
    const section = VerseSection(
      id: 1,
      startVerse: 5,
      endVerse: 8,
      reference: 'John 3:5-8',
    );

    expect(section.label, '5–8');
  });

  test('uses single verse label when section is one verse', () {
    const section = VerseSection(
      id: 1,
      startVerse: 16,
      endVerse: 16,
      reference: 'John 3:16',
    );

    expect(section.label, '16');
  });

  test('parses word study json when define mode payload is returned', () {
    final study = WordStudy.fromJson({
      'reference': 'Genesis 1:1',
      'version_id': 'bsb',
      'verses': [
        {
          'verse': 1,
          'groups': [
            {
              'phrase': 'In the beginning',
              'strongs': 'H7225',
              'lemma': 'רֵאשִׁית',
              'definition': 'the first',
            },
          ],
        },
      ],
    });

    expect(study.versionId, 'bsb');
    expect(study.allGroups.single.phrase, 'In the beginning');
    expect(study.allGroups.single.strongs, 'H7225');
    expect(study.allGroups.single.lemma, 'רֵאשִׁית');
  });
}
