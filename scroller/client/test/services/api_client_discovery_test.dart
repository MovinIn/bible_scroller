import 'dart:convert';

import 'package:bible_scroller/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('requests discovery endpoint with limit and exclude ids when fetching discovery reels', () async {
    Uri? requested;

    final client = ApiClient(
      baseUrl: 'http://example.test',
      deviceId: 'device-1',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 7,
                'reference': 'John 3:16',
                'book': 'John',
                'chapter': 3,
                'start_verse': 16,
                'end_verse': 16,
                'slug': 'John_3_16-16',
                'image_url': 'https://example.com/7.png',
                'iq_book_id': '43',
                'like_count': 2,
                'comment_count': 0,
                'liked_by_me': false,
              },
            ],
            'next_cursor': 7,
            'prev_cursor': null,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final feed = await client.fetchDiscoveryReels(
      limit: 10,
      excludeIds: const [1, 2, 3],
    );

    expect(requested!.path, '/reels/discovery');
    expect(requested!.queryParameters['limit'], '10');
    expect(requested!.queryParameters['exclude'], '1,2,3');
    expect(feed.items.single.id, 7);
    expect(feed.nextCursor, 7);
    expect(feed.prevCursor, isNull);
  });

  test('omits exclude query when exclude ids are empty', () async {
    Uri? requested;

    final client = ApiClient(
      baseUrl: 'http://example.test',
      deviceId: 'device-1',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({'items': [], 'next_cursor': null, 'prev_cursor': null}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await client.fetchDiscoveryReels(limit: 5);

    expect(requested!.path, '/reels/discovery');
    expect(requested!.queryParameters['limit'], '5');
    expect(requested!.queryParameters.containsKey('exclude'), isFalse);
  });
}
