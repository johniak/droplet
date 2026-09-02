import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:flutter_test/flutter_test.dart';

GameFileModel f(
  int id,
  String name,
  FileRole role, {
  String version = '',
  int size = 10,
}) =>
    GameFileModel(
      id: id,
      name: name,
      relativePath: 'sw/$name',
      role: role,
      discNumber: null,
      version: version,
      size: size,
    );

final settings = StorageSettings('/roms', {});

void main() {
  final files = [
    f(1, 'hk.nsp', FileRole.base),
    f(2, 'upd.nsp', FileRole.update, version: 'v2'),
  ];

  test('all present -> installed', () {
    final s = diffGame(
      files,
      {'hk.nsp': 10, 'upd.nsp': 10},
      settings,
      'switch',
      'HK',
    );
    expect(s.status, InstallStatus.installed);
    expect(s.updateAvailable, false);
  });

  test('none present -> none', () {
    final s = diffGame(files, {}, settings, 'switch', 'HK');
    expect(s.status, InstallStatus.none);
    expect(s.missing.length, 2);
  });

  test('size mismatch means missing', () {
    final s = diffGame(
      files,
      {'hk.nsp': 999, 'upd.nsp': 10},
      settings,
      'switch',
      'HK',
    );
    expect(s.status, InstallStatus.partial);
  });

  test('base without newest update -> updateAvailable', () {
    final s = diffGame(files, {'hk.nsp': 10}, settings, 'switch', 'HK');
    expect(s.status, InstallStatus.partial);
    expect(s.updateAvailable, true);
  });

  test('presentPaths includes files outside selection', () {
    final withOld = [
      ...files,
      f(3, 'old-upd.nsp', FileRole.update, version: 'v1'),
    ];
    final s = diffGame(
      withOld,
      {'hk.nsp': 10, 'old-upd.nsp': 10},
      settings,
      'switch',
      'HK',
    );
    expect(s.presentPaths, contains('/roms/switch/HK/old-upd.nsp'));
  });

  test('names with subdirectories keep their path inside the game folder', () {
    final s = diffGame(
      [f(1, 'disc1/ff7.bin', FileRole.disc)],
      {'disc1/ff7.bin': 10},
      settings,
      'psx',
      'FF7',
    );
    expect(s.presentPaths, ['/roms/psx/FF7/disc1/ff7.bin']);
  });
}
