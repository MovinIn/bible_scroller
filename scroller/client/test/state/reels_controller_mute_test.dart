import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_scroller/models/models.dart';
import 'package:bible_scroller/services/api_client.dart';
import 'package:bible_scroller/services/storage_service.dart';
import 'package:bible_scroller/state/reels_controller.dart';

class _FakeApi extends ApiClient {
  _FakeApi() : super(deviceId: 'test-device');

  @override
  Future<ReelFeed> fetchReels({int? cursor, int? beforeId, int? fromId, String? book, int limit = 10}) async {
    return const ReelFeed(items: [], nextCursor: null);
  }

  @override
  Future<List<String>> fetchBooks() async => const [];

  @override
  Future<List<BibleVersion>> fetchVersions() async {
    return const [
      BibleVersion(versionId: 'niv', name: 'New International Version'),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bible_scroller_mute_');
    SharedPreferences.setMockInitialValues({});
    Hive.init(tempDir.path);
    storage = StorageService();
    await storage.init(hivePath: tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('isMuted is false when voice mute preference is not stored', () async {
    final controller = ReelsController(api: _FakeApi(), storage: storage);

    await controller.initialize();

    expect(controller.isMuted, isFalse);
  });

  test('isMuted is true when voice mute preference is stored as muted', () async {
    await storage.saveVoiceMuted(true);
    final controller = ReelsController(api: _FakeApi(), storage: storage);

    await controller.initialize();

    expect(controller.isMuted, isTrue);
  });

  test('toggleMute sets isMuted to true when voice was unmuted', () async {
    final controller = ReelsController(api: _FakeApi(), storage: storage);
    await controller.initialize();

    await controller.toggleMute();

    expect(controller.isMuted, isTrue);
  });

  test('toggleMute sets isMuted to false when voice was muted', () async {
    final controller = ReelsController(api: _FakeApi(), storage: storage);
    await controller.initialize();
    await controller.toggleMute();

    await controller.toggleMute();

    expect(controller.isMuted, isFalse);
  });

  test('persists voice muted preference when toggleMute is called', () async {
    final controller = ReelsController(api: _FakeApi(), storage: storage);
    await controller.initialize();

    await controller.toggleMute();

    expect(await storage.readVoiceMuted(), isTrue);
  });
}
