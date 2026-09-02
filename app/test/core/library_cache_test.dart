import 'dart:io';

import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/cache/library_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('save/load roundtrip', () async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    final cache = LibraryCache(dir.path);
    await cache.save(
      [const SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 1)],
      [
        const GameSummary(
          id: 1,
          title: 'Mario',
          systemCode: 'snes',
          hasCover: true,
          totalSize: 5,
        ),
      ],
    );
    final loaded = await cache.load();
    expect(loaded!.games.single.title, 'Mario');
    expect(loaded.systems.single.code, 'snes');
    expect(loaded.savedAt.isBefore(DateTime.now().add(const Duration(minutes: 1))), true);
  });

  test('load returns null without file', () async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(await LibraryCache(dir.path).load(), isNull);
  });
}
