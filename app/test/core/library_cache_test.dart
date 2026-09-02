import 'dart:convert';
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
          folder: 'Mario (USA)',
        ),
      ],
      const [
        ManifestEntry(
          gameId: 1,
          systemCode: 'snes',
          folder: 'Mario (USA)',
          files: [
            GameFileModel(
              id: 1,
              name: 'Mario (USA).sfc',
              relativePath: '',
              role: FileRole.base,
              discNumber: null,
              version: '',
              size: 5,
            ),
          ],
        ),
      ],
    );
    final loaded = await cache.load();
    expect(loaded!.games.single.title, 'Mario');
    expect(loaded.games.single.folder, 'Mario (USA)');
    expect(loaded.systems.single.code, 'snes');
    expect(loaded.manifest.single.folder, 'Mario (USA)');
    expect(loaded.manifest.single.files.single.name, 'Mario (USA).sfc');
    expect(loaded.savedAt.isBefore(DateTime.now().add(const Duration(minutes: 1))), true);
  });

  test('an older cache file without the manifest key loads as empty', () async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/library.json').writeAsStringSync(
      jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'systems': const <Map<String, dynamic>>[],
        'games': const <Map<String, dynamic>>[],
      }),
    );
    final loaded = await LibraryCache(dir.path).load();
    expect(loaded!.manifest, isEmpty);
  });

  test('a legacy cache file without game folders loads as null', () async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/library.json').writeAsStringSync(
      jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'systems': const <Map<String, dynamic>>[],
        'games': [
          {
            'id': 1,
            'title': 'Mario',
            'system_code': 'snes',
            'has_cover': true,
            'total_size': 5,
          },
        ],
      }),
    );
    expect(await LibraryCache(dir.path).load(), isNull);
  });

  test('a cache file that is not JSON at all loads as null', () async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/library.json').writeAsStringSync('nie-json');
    expect(await LibraryCache(dir.path).load(), isNull);
  });

  test('load returns null without file', () async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(await LibraryCache(dir.path).load(), isNull);
  });
}
