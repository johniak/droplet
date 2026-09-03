import 'dart:io';

import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/device_scan.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:flutter_test/flutter_test.dart';

GameFileModel f(int id, String name, FileRole role, {String version = '', int size = 4}) =>
    GameFileModel(id: id, name: name, relativePath: '', role: role, discNumber: null,
        version: version, size: size);

void main() {
  late Directory root;
  late StorageSettings settings;

  setUp(() {
    root = Directory.systemTemp.createTempSync('roms');
    settings = StorageSettings(root.path, const {});
  });
  tearDown(() => root.deleteSync(recursive: true));

  void put(String rel, [int size = 4]) {
    final file = File('${root.path}/$rel')..parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(size, 0));
  }

  /// Klucze znanych folderów idą po rozwiązanym katalogu, nie po kodzie.
  Set<String> known(Map<String, String> folders) => {
        for (final e in folders.entries) knownFolderKey(settings, e.key, e.value),
      };

  test('known folders are indexed, everything else is unknown', () {
    put('snes/Mario (USA)/Mario (USA).sfc');
    put('snes/Zelda (USA)/z.sfc');          // nieznany folder
    put('snes/loose.sfc', 2);               // plik luzem
    put('psx/FF7/disc1/FF7 (Disc 1).bin', 8);
    final index = scanDevice(settings, ['snes', 'psx', 'gba'], known({'snes': 'Mario (USA)', 'psx': 'FF7'}));
    expect(index.games['snes']!['Mario (USA)'], {'Mario (USA).sfc': 4});
    expect(index.games['psx']!['FF7'], {'disc1/FF7 (Disc 1).bin': 8});
    expect(index.games.containsKey('gba'), isFalse);
    final unknown = {for (final u in index.unknown) u.path: (u.bytes, u.isDirectory)};
    expect(unknown, {
      '${root.path}/snes/Zelda (USA)': (4, true),
      '${root.path}/snes/loose.sfc': (2, false),
    });
    expect(index.unknown.every((u) => u.systemCode == 'snes'), isTrue);
  });

  test('buildLocalStates derives every game state from one index', () {
    put('snes/Mario (USA)/Mario (USA).sfc');
    put('switch/HK/hk.nsp');
    final manifest = [
      ManifestEntry(gameId: 1, systemCode: 'snes', folder: 'Mario (USA)',
          files: [f(1, 'Mario (USA).sfc', FileRole.base)]),
      ManifestEntry(gameId: 2, systemCode: 'switch', folder: 'HK',
          files: [f(2, 'hk.nsp', FileRole.base), f(3, 'upd.nsp', FileRole.update, version: 'v2')]),
      ManifestEntry(gameId: 3, systemCode: 'snes', folder: 'Absent',
          files: [f(4, 'a.sfc', FileRole.base)]),
    ];
    final index = scanDevice(settings, ['snes', 'switch'],
        {...known({'snes': 'Mario (USA)', 'switch': 'HK'}), knownFolderKey(settings, 'snes', 'Absent')});
    final states = buildLocalStates(manifest, index, settings);
    expect(states[1]!.status, InstallStatus.installed);
    expect(states[1]!.presentPaths, ['${root.path}/snes/Mario (USA)/Mario (USA).sfc']);
    expect(states[2]!.status, InstallStatus.partial);
    expect(states[2]!.updateAvailable, isTrue);
    expect(states[3]!.status, InstallStatus.none);
  });

  test('hidden files and folders are skipped, not reported as unknown', () {
    put('snes/Mario (USA)/Mario (USA).sfc');
    put('snes/Mario (USA)/.DS_Store', 9);
    put('snes/Mario (USA)/.thumbs/cache.png', 9);
    put('snes/.nomedia', 1);
    put('snes/.thumbnails/x.png', 7);
    final index = scanDevice(settings, ['snes'], known({'snes': 'Mario (USA)'}));
    expect(index.games['snes']!['Mario (USA)'], {'Mario (USA).sfc': 4});
    expect(index.unknown, isEmpty);
  });

  test('a system path that is a file yields nothing and does not throw', () {
    put('snes', 4); // "katalog" systemu okazuje się plikiem
    expect(scanDevice(settings, ['snes'], const {}).games, isEmpty);
    expect(scanDevice(settings, ['snes'], const {}).unknown, isEmpty);
  });

  test('unreadable directories are skipped, the rest of the scan goes on', () {
    put('snes/Mario (USA)/Mario (USA).sfc');
    put('snes/Mario (USA)/locked/secret.sfc', 6);
    put('psx/FF7/disc1/FF7 (Disc 1).bin', 8);
    final locked = '${root.path}/snes/Mario (USA)/locked';
    final lockedSystem = '${root.path}/psx';
    Process.runSync('chmod', ['000', locked]);
    Process.runSync('chmod', ['000', lockedSystem]);
    addTearDown(() {
      Process.runSync('chmod', ['700', locked]);
      Process.runSync('chmod', ['700', lockedSystem]);
    });
    final index = scanDevice(settings, ['snes', 'psx'], known({'snes': 'Mario (USA)', 'psx': 'FF7'}));
    // Nieczytelny podkatalog nie gubi reszty plików gry...
    expect(index.games['snes']!['Mario (USA)'], {'Mario (USA).sfc': 4});
    // ...a nieczytelny katalog systemu po prostu wypada ze skanu.
    expect(index.games.containsKey('psx'), isFalse);
    expect(index.unknown, isEmpty);
  });

  test('size mismatch means not present', () {
    put('snes/Mario (USA)/Mario (USA).sfc', 3);
    final manifest = [
      ManifestEntry(gameId: 1, systemCode: 'snes', folder: 'Mario (USA)',
          files: [f(1, 'Mario (USA).sfc', FileRole.base)]),
    ];
    final index = scanDevice(settings, ['snes'], known({'snes': 'Mario (USA)'}));
    expect(buildLocalStates(manifest, index, settings)[1]!.status, InstallStatus.none);
  });

  test('an empty override falls back to the code, never to the ROM dir', () {
    // Nadpisanie „" dawało kiedyś `<roms>/`, więc skan listował sam katalog
    // ROMów i każdy katalog systemu wychodził jako nieznany.
    put('snes/Mario (USA)/Mario (USA).sfc');
    final blank = StorageSettings(root.path, const {'snes': '  '});
    expect(blank.dirFor('snes'), '${root.path}/snes');
    final index = scanDevice(
      blank,
      ['snes'],
      {knownFolderKey(blank, 'snes', 'Mario (USA)')},
    );
    expect(index.games['snes']!['Mario (USA)'], {'Mario (USA).sfc': 4});
    expect(index.unknown, isEmpty);
  });

  test('two systems sharing one directory do not cross-list each other', () {
    put('gameboy/Tetris/t.gb');
    put('gameboy/Zelda DX/z.gbc');
    final shared = StorageSettings(
      root.path,
      const {'gb': 'gameboy', 'gbc': 'gameboy'},
    );
    final index = scanDevice(shared, ['gb', 'gbc'], {
      knownFolderKey(shared, 'gb', 'Tetris'),
      knownFolderKey(shared, 'gbc', 'Zelda DX'),
    });
    expect(index.unknown, isEmpty);
    // Katalog przeskanowany raz, ale rozmiary widoczne dla obu kodów — każdy
    // wpis manifestu szuka po swoim.
    expect(index.games['gb']!['Tetris'], {'t.gb': 4});
    expect(index.games['gbc']!['Zelda DX'], {'z.gbc': 4});
  });

  test('a system dir outside the ROM tree is not scanned at all', () {
    put('snes/Mario (USA)/Mario (USA).sfc');
    // `..` nie przejdzie przez repozytorium, ale `StorageSettings` zbudowane
    // wprost (albo stary zapis w prefsach) nie ma prawa wyprowadzić skanu.
    final escaping = StorageSettings('${root.path}/snes', const {});
    expect(
      scanDevice(escaping, ['..'], const {}).unknown,
      isEmpty,
    );
  });

  test('sizes stay relative when the base path ends with a slash', () {
    put('snes/Mario (USA)/disc1/a.bin', 5);
    expect(
      sizesUnder(Directory('${root.path}/snes/Mario (USA)/')),
      {'disc1/a.bin': 5},
    );
  });
}
