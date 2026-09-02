import 'dart:async';
import 'dart:io';

import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

GameFileModel _file(int id, String name, {int size = 4}) => GameFileModel(
      id: id,
      name: name,
      relativePath: '',
      role: FileRole.base,
      discNumber: null,
      version: '',
      size: size,
    );

const _systems = [
  SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 2),
];

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('index'));
  tearDown(() => root.deleteSync(recursive: true));

  void put(String rel, [int size = 4]) {
    final file = File('${root.path}/$rel')..parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(size, 0));
  }

  ProviderContainer container(List<ManifestEntry> manifest) {
    final c = ProviderContainer(
      overrides: [
        storageSettingsProvider.overrideWith(
          (ref) async => StorageSettings(root.path, const {}),
        ),
        librarySnapshotProvider.overrideWith(
          (ref) async => LibrarySnapshot(
            systems: _systems,
            games: const [],
            manifest: manifest,
            fromCache: false,
            previousIds: const {},
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  final manifest = [
    ManifestEntry(
      gameId: 1,
      systemCode: 'snes',
      folder: 'Mario (USA)',
      files: [_file(1, 'Mario (USA).sfc')],
    ),
    ManifestEntry(
      gameId: 2,
      systemCode: 'snes',
      folder: 'Zelda (USA)',
      files: [_file(2, 'a.sfc'), _file(3, 'b.sfc')],
    ),
  ];

  test('one scan feeds every game state, the id sets and the strays', () async {
    put('snes/Mario (USA)/Mario (USA).sfc');
    put('snes/Zelda (USA)/a.sfc');
    put('snes/Other/x.sfc', 7);
    final c = container(manifest);

    final states = await c.read(deviceIndexProvider.future);
    expect(states[1]!.status, InstallStatus.installed);
    expect(states[2]!.status, InstallStatus.partial);
    expect(c.read(installedIdsProvider), {1, 2});
    expect(
      c.read(unknownOnDeviceProvider).map((u) => u.path),
      ['${root.path}/snes/Other'],
    );
    expect(await c.read(localStateProvider(1).future), states[1]);
  });

  test('updatableIds follow the newest update on disk', () async {
    put('snes/HK/hk.nsp');
    final c = container([
      ManifestEntry(
        gameId: 5,
        systemCode: 'snes',
        folder: 'HK',
        files: [
          _file(1, 'hk.nsp'),
          GameFileModel(
            id: 2,
            name: 'upd.nsp',
            relativePath: '',
            role: FileRole.update,
            discNumber: null,
            version: 'v2',
            size: 4,
          ),
        ],
      ),
    ]);
    expect(
      (await c.read(deviceIndexProvider.future))[5]!.status,
      InstallStatus.partial,
    );
    expect(c.read(updatableIdsProvider), {5});
    expect(c.read(installedIdsProvider), {5});
  });

  test('refresh rescans the disk without touching the network', () async {
    put('snes/Zelda (USA)/a.sfc');
    final c = container(manifest);
    expect(
      (await c.read(deviceIndexProvider.future))[2]!.status,
      InstallStatus.partial,
    );

    put('snes/Zelda (USA)/b.sfc');
    await c.read(deviceIndexProvider.notifier).refresh();
    expect(
      c.read(deviceIndexProvider).value![2]!.status,
      InstallStatus.installed,
    );
    expect(c.read(installedIdsProvider), {2});
  });

  test('refresh before the first scan finished does nothing', () async {
    final pending = Completer<LibrarySnapshot>();
    addTearDown(() => pending.complete(
          const LibrarySnapshot(
            systems: [],
            games: [],
            manifest: [],
            fromCache: false,
            previousIds: {},
          ),
        ));
    final c = ProviderContainer(
      overrides: [
        storageSettingsProvider.overrideWith(
          (ref) async => StorageSettings(root.path, const {}),
        ),
        librarySnapshotProvider.overrideWith((ref) => pending.future),
      ],
    );
    addTearDown(c.dispose);
    await c.read(deviceIndexProvider.notifier).refresh();
    expect(c.read(deviceIndexProvider).hasValue, isFalse);
  });

  test('a game outside the manifest is simply not installed', () async {
    final c = container(manifest);
    expect(await c.read(localStateProvider(99).future), kNotInstalled);
  });
}
