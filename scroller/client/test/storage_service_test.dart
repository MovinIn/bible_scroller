import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_scroller/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('bible_scroller_hive_');
    Hive.init(tempDir.path);
    try {
      await Hive.deleteBoxFromDisk('liked_reels');
      await Hive.deleteBoxFromDisk('verse_cache');
    } catch (_) {}
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('returns cached verse text when reel was previously stored', () async {
    final storage = StorageService();
    await storage.init(hivePath: tempDir.path);

    await storage.cacheVerseText(reelId: 1, versionId: 'kjv', text: 'For God so loved the world');

    final cached = await storage.readCachedVerseText(reelId: 1, versionId: 'kjv');

    expect(cached, 'For God so loved the world');
  });

  test('returns null when verse text was never cached', () async {
    final storage = StorageService();
    await storage.init(hivePath: tempDir.path);

    final cached = await storage.readCachedVerseText(reelId: 99, versionId: 'kjv');

    expect(cached, isNull);
  });

  test('returns cached verse text after relaunch when box was not opened in init', () async {
    final writer = StorageService();
    await writer.init(hivePath: tempDir.path);
    await writer.cacheVerseText(
      reelId: 7,
      versionId: 'niv',
      text: 'In the beginning God created',
    );
    await Hive.close();

    final reader = StorageService();
    await reader.init(hivePath: tempDir.path);

    final cached = await reader.readCachedVerseText(reelId: 7, versionId: 'niv');

    expect(cached, 'In the beginning God created');
  });
}
