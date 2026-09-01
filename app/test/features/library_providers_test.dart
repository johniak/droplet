import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ProviderContainer> _signedInContainer(ApiClient client) async {
  final repo = SessionRepository(MemoryKeyValueStore());
  await repo.save(const Session(serverUrl: 'http://nas:8000', token: 't'));
  final container = ProviderContainer(
    overrides: [
      sessionRepositoryProvider.overrideWithValue(repo),
      apiClientFactoryProvider.overrideWithValue((baseUrl, {token}) => client),
    ],
  );
  await container.read(sessionProvider.future);
  return container;
}

void main() {
  test('gamesProvider walks every page until hasNext is false', () async {
    final client = _PagingClient();
    final container = await _signedInContainer(client);
    addTearDown(container.dispose);

    final games = await container.read(gamesProvider.future);
    expect(games.map((g) => g.title), ['Mario', 'Tekken']);
    expect(client.requestedPages, [1, 2]);
  });

  test('gamesProvider forwards the selected system and search', () async {
    final client = _PagingClient();
    final container = await _signedInContainer(client);
    addTearDown(container.dispose);

    container.read(selectedSystemProvider.notifier).select('psx');
    container.read(searchQueryProvider.notifier).update('tek');
    await container.read(gamesProvider.future);
    expect(client.lastSystem, 'psx');
    expect(client.lastSearch, 'tek');
  });

  test('systemsProvider reads the systems endpoint', () async {
    final client = _PagingClient();
    final container = await _signedInContainer(client);
    addTearDown(container.dispose);

    final systems = await container.read(systemsProvider.future);
    expect(systems.single.code, 'snes');
  });
}

class _PagingClient extends ApiClient {
  _PagingClient() : super(baseUrl: 'http://nas:8000', token: 't');

  final List<int> requestedPages = [];
  String? lastSystem;
  String? lastSearch;

  @override
  Future<GamePage> fetchGames({
    String? system,
    String? search,
    int page = 1,
  }) async {
    requestedPages.add(page);
    lastSystem = system;
    lastSearch = search;
    final title = page == 1 ? 'Mario' : 'Tekken';
    return GamePage(
      count: 2,
      hasNext: page == 1,
      results: [
        GameSummary(
          id: page,
          title: title,
          systemCode: 'snes',
          hasCover: false,
          totalSize: 1,
        ),
      ],
    );
  }

  @override
  Future<List<SystemModel>> fetchSystems() async => [
        const SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 2),
      ];
}
