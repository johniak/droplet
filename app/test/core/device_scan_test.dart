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

  test('known folders are indexed, everything else is unknown', () {
    put('snes/Mario (USA)/Mario (USA).sfc');
    put('snes/Zelda (USA)/z.sfc');          // nieznany folder
    put('snes/loose.sfc', 2);               // plik luzem
    put('psx/FF7/disc1/FF7 (Disc 1).bin', 8);
    final index = scanDevice(settings, ['snes', 'psx', 'gba'], {'snes/Mario (USA)', 'psx/FF7'});
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
    final index = scanDevice(settings, ['snes', 'switch'], {'snes/Mario (USA)', 'switch/HK', 'snes/Absent'});
    final states = buildLocalStates(manifest, index, settings);
    expect(states[1]!.status, InstallStatus.installed);
    expect(states[1]!.presentPaths, ['${root.path}/snes/Mario (USA)/Mario (USA).sfc']);
    expect(states[2]!.status, InstallStatus.partial);
    expect(states[2]!.updateAvailable, isTrue);
    expect(states[3]!.status, InstallStatus.none);
  });

  test('size mismatch means not present', () {
    put('snes/Mario (USA)/Mario (USA).sfc', 3);
    final manifest = [
      ManifestEntry(gameId: 1, systemCode: 'snes', folder: 'Mario (USA)',
          files: [f(1, 'Mario (USA).sfc', FileRole.base)]),
    ];
    final index = scanDevice(settings, ['snes'], {'snes/Mario (USA)'});
    expect(buildLocalStates(manifest, index, settings)[1]!.status, InstallStatus.none);
  });
}
