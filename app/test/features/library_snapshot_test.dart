import 'dart:io';

import 'package:dio/dio.dart';
import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/cache/library_cache.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _mario = GameSummary(
  id: 1,
  title: 'Mario',
  systemCode: 'snes',
  hasCover: false,
  totalSize: 5,
  folder: 'Mario (USA)',
);
const _tekken = GameSummary(
  id: 2,
  title: 'Tekken',
  systemCode: 'psx',
  hasCover: false,
  totalSize: 9,
  folder: 'Tekken (USA)',
);
const _marioEntry = ManifestEntry(
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
);
const _tekkenEntry = ManifestEntry(
  gameId: 2,
  systemCode: 'psx',
  folder: 'Tekken (USA)',
  files: [],
);

class _OkClient extends ApiClient {
  _OkClient() : super(baseUrl: 'http://nas:8000', token: 't');

  final pages = <int>[];

  @override
  Future<List<SystemModel>> fetchSystems() async => [
    const SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 1),
  ];

  @override
  Future<GamePage> fetchGames({
    String? system,
    String? search,
    int page = 1,
  }) async {
    pages.add(page);
    return GamePage(
      count: 2,
      hasNext: page == 1,
      results: [page == 1 ? _mario : _tekken],
    );
  }

  @override
  Future<List<ManifestEntry>> fetchManifest() async => const [
    _marioEntry,
    _tekkenEntry,
  ];
}

const _biosPack = GameSummary(
  id: 3,
  title: 'RetroArch',
  systemCode: 'bios',
  hasCover: false,
  totalSize: 4,
  folder: 'RetroArch',
);
const _biosEntry = ManifestEntry(
  gameId: 3,
  systemCode: 'bios',
  folder: 'RetroArch',
  files: [
    GameFileModel(
      id: 10,
      name: 'scph1001.bin',
      relativePath: '',
      role: FileRole.other,
      discNumber: null,
      version: '',
      size: 4,
    ),
  ],
);

class _OkClientWithBios extends ApiClient {
  _OkClientWithBios() : super(baseUrl: 'http://nas:8000', token: 't');

  @override
  Future<List<SystemModel>> fetchSystems() async => [
    const SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 1),
    const SystemModel(
      id: 2,
      code: 'bios',
      name: 'BIOS & firmware',
      gameCount: 1,
    ),
  ];

  @override
  Future<GamePage> fetchGames({
    String? system,
    String? search,
    int page = 1,
  }) async => GamePage(count: 2, hasNext: false, results: [_mario, _biosPack]);

  @override
  Future<List<ManifestEntry>> fetchManifest() async => const [
    _marioEntry,
    _biosEntry,
  ];
}

class _OfflineClient extends ApiClient {
  _OfflineClient() : super(baseUrl: 'http://nas:8000', token: 't');

  @override
  Future<List<SystemModel>> fetchSystems() async => throw DioException(
    requestOptions: RequestOptions(path: '/api/systems/'),
    type: DioExceptionType.connectionError,
  );
}

ProviderContainer _container(ApiClient client, Directory dir) =>
    ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        libraryCacheProvider.overrideWith(
          (ref) async => LibraryCache(dir.path),
        ),
      ],
    );

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync());
  tearDown(() => dir.deleteSync(recursive: true));

  test('a successful refresh fills the cache', () async {
    final client = _OkClient();
    final container = _container(client, dir);
    addTearDown(container.dispose);

    final snapshot = await container.read(librarySnapshotProvider.future);
    expect(snapshot.fromCache, false);
    expect(snapshot.games.map((g) => g.title), ['Mario', 'Tekken']);
    expect(client.pages, [1, 2]);
    expect(container.read(isOfflineProvider), false);
    expect(snapshot.manifest.length, 2);
    expect(snapshot.manifest.first.folder, 'Mario (USA)');
    final cached = (await LibraryCache(dir.path).load())!;
    expect(cached.games.length, 2);
    expect(cached.manifest.length, 2);
  });

  test('a network error falls back to the cache', () async {
    await LibraryCache(dir.path).save(
      [const SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 1)],
      [_mario],
      const [_marioEntry],
    );
    final container = _container(_OfflineClient(), dir);
    addTearDown(container.dispose);

    final snapshot = await container.read(librarySnapshotProvider.future);
    expect(snapshot.fromCache, true);
    expect(snapshot.games.single.title, 'Mario');
    expect(snapshot.manifest.single.folder, 'Mario (USA)');
    expect(container.read(isOfflineProvider), true);
  });

  test('a network error without a cache surfaces the error', () async {
    final container = _container(_OfflineClient(), dir);
    addTearDown(container.dispose);
    // In Riverpod 3 the `.future` of an errored provider stays pending unless
    // something listens, so the state is observed instead.
    container.listen(librarySnapshotProvider, (_, __) {}, onError: (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final state = container.read(librarySnapshotProvider);
    expect(state.hasError, true);
    expect(state.error.toString(), contains('DioException'));
    expect(container.read(isOfflineProvider), false);
  });

  test('previousIds carry the ids known before the refresh', () async {
    await LibraryCache(dir.path).save(const [], [_mario], const [_marioEntry]);
    final container = _container(_OkClient(), dir);
    addTearDown(container.dispose);
    final snapshot = await container.read(librarySnapshotProvider.future);
    expect(snapshot.previousIds, {1});
  });

  test('the games projection filters by search', () async {
    final container = _container(_OkClient(), dir);
    addTearDown(container.dispose);
    expect((await container.read(gamesProvider.future)).length, 2);

    container.read(searchQueryProvider.notifier).update('mar');
    expect((await container.read(gamesProvider.future)).single.title, 'Mario');
  });

  test('systemsProvider projects the snapshot', () async {
    final container = _container(_OkClient(), dir);
    addTearDown(container.dispose);
    expect((await container.read(systemsProvider.future)).single.code, 'snes');
  });

  test('the snapshot splits bios packs out of games and systems', () async {
    final container = _container(_OkClientWithBios(), dir);
    addTearDown(container.dispose);
    final snapshot = await container.read(librarySnapshotProvider.future);
    expect(snapshot.games.map((g) => g.systemCode), isNot(contains('bios')));
    expect(snapshot.systems.map((s) => s.code), isNot(contains('bios')));
    expect(snapshot.games.length, 1);
    expect(snapshot.systems.length, 1);
    expect(snapshot.supportPacks.single.title, 'RetroArch');
    // The manifest stays complete — the device scan still needs to know the
    // `bios` folder.
    expect(
      snapshot.manifest.map((e) => e.systemCode),
      containsAll(['snes', 'bios']),
    );
  });

  test('previousIds never count support packs as new', () async {
    await LibraryCache(dir.path).save(
      [
        const SystemModel(
          id: 2,
          code: 'bios',
          name: 'BIOS & firmware',
          gameCount: 1,
        ),
      ],
      [_biosPack],
      const [_biosEntry],
    );
    final container = _container(_OkClientWithBios(), dir);
    addTearDown(container.dispose);
    final snapshot = await container.read(librarySnapshotProvider.future);
    expect(snapshot.previousIds, isEmpty);
  });
}
