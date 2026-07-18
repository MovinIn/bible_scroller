import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/models.dart';

class ApiClient {
  ApiClient({
    http.Client? client,
    String? baseUrl,
    String? deviceId,
  })  : _client = client ?? http.Client(),
        _baseUrl = resolveApiBaseUrl(baseUrl).replaceAll(RegExp(r'/+$'), ''),
        _deviceId = deviceId ?? const Uuid().v4();

  /// Mobile default is the Android emulator host. On web, an empty
  /// `--dart-define=API_BASE_URL=` uses the page origin (same-host deploy).
  static String resolveApiBaseUrl([String? override]) {
    const fromEnv = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000',
    );
    final configured = override ?? fromEnv;
    if (kIsWeb && configured.isEmpty) {
      return Uri.base.origin;
    }
    return configured;
  }

  final http.Client _client;
  final String _baseUrl;
  final String _deviceId;
  String? accessToken;

  String get deviceId => _deviceId;
  String get baseUrl => _baseUrl;

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Device-Id': _deviceId,
    };
    final token = accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<ReelFeed> fetchReels({
    int? cursor,
    int? beforeId,
    int? fromId,
    String? book,
    int limit = 10,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (cursor != null) {
      query['cursor'] = '$cursor';
    }
    if (beforeId != null) {
      query['before_id'] = '$beforeId';
    }
    if (fromId != null) {
      query['from_id'] = '$fromId';
    }
    if (book != null && book.isNotEmpty) {
      query['book'] = book;
    }
    final uri = Uri.parse('$_baseUrl/reels').replace(queryParameters: query);
    final response = await _client.get(uri, headers: _headers);
    _ensureSuccess(response);
    return ReelFeed.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<String>> fetchBooks() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/reels/books'),
      headers: _headers,
    );
    _ensureSuccess(response);
    final items = jsonDecode(response.body) as List<dynamic>;
    return items.map((item) => item as String).toList();
  }

  Future<LikeStatus> likeReel(int reelId) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/reels/$reelId/like'),
      headers: _headers,
    );
    _ensureSuccess(response);
    return LikeStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<LikeStatus> unlikeReel(int reelId) async {
    final response = await _client.delete(
      Uri.parse('$_baseUrl/reels/$reelId/like'),
      headers: _headers,
    );
    _ensureSuccess(response);
    return LikeStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<Comment>> fetchComments(int reelId) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/reels/$reelId/comments'),
      headers: _headers,
    );
    _ensureSuccess(response);
    final items = jsonDecode(response.body) as List<dynamic>;
    return items
        .map((item) => Comment.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Comment> postComment(int reelId, String body, {int? parentId}) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/reels/$reelId/comments'),
      headers: _headers,
      body: jsonEncode({
        'body': body,
        if (parentId != null) 'parent_id': parentId,
      }),
    );
    _ensureSuccess(response);
    return Comment.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<LikeStatus> likeComment(int commentId) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/comments/$commentId/like'),
      headers: _headers,
    );
    _ensureSuccess(response);
    return LikeStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<LikeStatus> unlikeComment(int commentId) async {
    final response = await _client.delete(
      Uri.parse('$_baseUrl/comments/$commentId/like'),
      headers: _headers,
    );
    _ensureSuccess(response);
    return LikeStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<BibleVersion>> fetchVersions() async {
    final response = await _client.get(Uri.parse('$_baseUrl/bible/versions'));
    _ensureSuccess(response);
    final items = jsonDecode(response.body) as List<dynamic>;
    return items
        .map((item) => BibleVersion.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<BibleVerse> fetchVerse({
    required Reel reel,
    required String versionId,
  }) async {
    final uri = Uri.parse('$_baseUrl/bible/verse').replace(
      queryParameters: {
        'book': reel.book,
        'chapter': '${reel.chapter}',
        'start_verse': '${reel.startVerse}',
        'end_verse': '${reel.endVerse}',
        'version_id': versionId,
      },
    );
    final response = await _client.get(uri);
    _ensureSuccess(response);
    return BibleVerse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<BibleAudio> fetchAudio({
    required Reel reel,
    required String versionId,
  }) async {
    final uri = Uri.parse('$_baseUrl/bible/audio').replace(
      queryParameters: {
        'book': reel.book,
        'chapter': '${reel.chapter}',
        'version_id': versionId,
      },
    );
    final response = await _client.get(uri);
    _ensureSuccess(response);
    return BibleAudio.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, response.body);
    }
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}
