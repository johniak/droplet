import 'dart:async';
import 'dart:io';

import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/device_scan.dart';
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

/// A few turns of the event loop, reading the index on each one: Riverpod
/// only recomputes an invalidated provider once something reads it — in the
/// app that's the widgets, in the test the loop has to do it.
Future<void> settle(ProviderContainer c, [int turns = 5]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
    c.read(deviceIndexProvider);
  }
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('index'));
  tearDown(() => root.deleteSync(recursive: true));

  void put(String rel, [int size = 4]) {
    final file = File('${root.path}/$rel')..parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(size, 0));
  }

  ProviderContainer container(
    List<ManifestEntry> manifest, {
    DeviceScanner? scan,
  }) {
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
        if (scan != null)
          deviceIndexProvider
              .overrideWith(() => DeviceIndexController(scan: scan)),
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

  test('a settings change rescans instead of rebuilding the index', () async {
    put('snes/Zelda (USA)/a.sfc');
    final c = container(manifest);
    expect(
      (await c.read(deviceIndexProvider.future))[2]!.status,
      InstallStatus.partial,
    );
    final notifier = c.read(deviceIndexProvider.notifier);

    put('snes/Zelda (USA)/b.sfc');
    c.invalidate(storageSettingsProvider);
    await settle(c);

    // Same notifier: the index wasn't invalidated, only recomputed.
    expect(identical(c.read(deviceIndexProvider.notifier), notifier), isTrue);
    expect(
      c.read(deviceIndexProvider).value![2]!.status,
      InstallStatus.installed,
    );
  });

  test('one invalidation of a dependency means one disk scan', () async {
    put('snes/Zelda (USA)/a.sfc');
    var scans = 0;
    final c = container(
      manifest,
      scan: (settings, codes, known) {
        scans++;
        return scanDevice(settings, codes, known);
      },
    );
    await c.read(deviceIndexProvider.future);
    expect(scans, 1);

    // Invalidation fires two notifications (loading + data) — but the scan should be one.
    c.invalidate(storageSettingsProvider);
    await settle(c);
    expect(scans, 2);

    c.invalidate(librarySnapshotProvider);
    await settle(c);
    expect(scans, 3);
  });

  test('a change during the first scan is applied after it finishes', () async {
    put('snes/Zelda (USA)/a.sfc');
    var scans = 0;
    final settings = Completer<StorageSettings>();
    final c = ProviderContainer(
      overrides: [
        storageSettingsProvider.overrideWith((ref) => settings.future),
        librarySnapshotProvider.overrideWith(
          (ref) async => LibrarySnapshot(
            systems: _systems,
            games: const [],
            manifest: manifest,
            fromCache: false,
            previousIds: const {},
          ),
        ),
        deviceIndexProvider.overrideWith(
          () => DeviceIndexController(
            scan: (s, codes, known) {
              scans++;
              return scanDevice(s, codes, known);
            },
          ),
        ),
      ],
    );
    addTearDown(c.dispose);

    final built = c.read(deviceIndexProvider.future);
    // Snapshot already loaded, `build` is waiting on the settings — now we
    // change the library, a dependency the first scan won't find out about.
    await settle(c);
    c.invalidate(librarySnapshotProvider);
    await settle(c);
    expect(scans, 0, reason: 'the first scan has not started yet');

    settings.complete(StorageSettings(root.path, const {}));
    await built;
    await settle(c);
    // The scan from `build` plus a rescan triggered by the change during
    // build — without it the index would sit on a stale library (see the
    // test above: a plain `build` counts exactly one scan).
    expect(scans, 2);
  });

  test('a failed first scan still rescans once the library loads', () async {
    put('snes/Zelda (USA)/a.sfc');
    var offline = true;
    final c = ProviderContainer(
      // Riverpod 3 retries a failed provider build on its own (keeping it in
      // `AsyncLoading` meanwhile); in the test we want to see the error right away.
      retry: (_, __) => null,
      overrides: [
        storageSettingsProvider.overrideWith(
          (ref) async => StorageSettings(root.path, const {}),
        ),
        librarySnapshotProvider.overrideWith((ref) async {
          if (offline) throw Exception('no network and no cache');
          return LibrarySnapshot(
            systems: _systems,
            games: const [],
            manifest: manifest,
            fromCache: false,
            previousIds: const {},
          );
        }),
      ],
    );
    addTearDown(c.dispose);

    await expectLater(
      c.read(deviceIndexProvider.future),
      throwsA(isA<Exception>()),
    );
    expect(c.read(deviceIndexProvider).hasValue, isFalse);

    offline = false;
    c.invalidate(librarySnapshotProvider);
    for (var i = 0; i < 20 && !c.read(deviceIndexProvider).hasValue; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(
      c.read(deviceIndexProvider).value![2]!.status,
      InstallStatus.partial,
    );
  });

  test('a game outside the manifest is simply not installed', () async {
    final c = container(manifest);
    expect(await c.read(localStateProvider(99).future), kNotInstalled);
  });
}
