import 'dart:io';

import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_scanner.dart';
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
    );
    expect(s.status, InstallStatus.installed);
    expect(s.updateAvailable, false);
  });

  test('none present -> none', () {
    final s = diffGame(files, {}, settings, 'switch');
    expect(s.status, InstallStatus.none);
    expect(s.missing.length, 2);
  });

  test('size mismatch means missing', () {
    final s = diffGame(
      files,
      {'hk.nsp': 999, 'upd.nsp': 10},
      settings,
      'switch',
    );
    expect(s.status, InstallStatus.partial);
  });

  test('base without newest update -> updateAvailable', () {
    final s = diffGame(files, {'hk.nsp': 10}, settings, 'switch');
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
    );
    expect(s.presentPaths, contains('/roms/switch/old-upd.nsp'));
  });

  group('scanSystemDir', () {
    test('missing dir -> empty map', () async {
      expect(await scanSystemDir('/nie/ma/takiego'), isEmpty);
    });

    test('maps basenames to sizes, skips subdirectories', () async {
      final dir = await Directory.systemTemp.createTemp();
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/a.sfc').writeAsBytesSync(List.filled(3, 0));
      File('${dir.path}/b.sfc').writeAsBytesSync(List.filled(5, 0));
      Directory('${dir.path}/sub').createSync();
      expect(await scanSystemDir(dir.path), {'a.sfc': 3, 'b.sfc': 5});
    });
  });
}
