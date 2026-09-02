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
);
const _tekken = GameSummary(
  id: 2,
  title: 'Tekken',
  systemCode: 'psx',
  hasCover: false,
  totalSize: 9,
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
        libraryCacheProvider.overrideWith((ref) async => LibraryCache(dir.path)),
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
    expect((await LibraryCache(dir.path).load())!.games.length, 2);
  });

  test('a network error falls back to the cache', () async {
    await LibraryCache(dir.path).save(
      [const SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 1)],
      [_mario],
    );
    final container = _container(_OfflineClient(), dir);
    addTearDown(container.dispose);

    final snapshot = await container.read(librarySnapshotProvider.future);
    expect(snapshot.fromCache, true);
    expect(snapshot.games.single.title, 'Mario');
    expect(container.read(isOfflineProvider), true);
  });

  test('a network error without a cache surfaces the error', () async {
    final container = _container(_OfflineClient(), dir);
    addTearDown(container.dispose);
    // In Riverpod 3 the `.future` of an errored provider stays pending unless
    // something listens, so the state is observed instead.
    container.listen(
      librarySnapshotProvider,
      (_, __) {},
      onError: (_, __) {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final state = container.read(librarySnapshotProvider);
    expect(state.hasError, true);
    expect(state.error.toString(), contains('DioException'));
    expect(container.read(isOfflineProvider), false);
  });

  test('previousIds carry the ids known before the refresh', () async {
    await LibraryCache(dir.path).save(const [], [_mario]);
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
}
