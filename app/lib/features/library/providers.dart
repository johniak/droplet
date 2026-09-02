import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/models.dart';
import '../../core/cache/library_cache.dart';
import '../../core/session/providers.dart';

final libraryCacheProvider = FutureProvider<LibraryCache>(
  (ref) async => LibraryCache((await getApplicationDocumentsDirectory()).path),
);

/// Everything the library screen needs, from one source: the server when it
/// answers, the last cached copy when it does not.
class LibrarySnapshot {
  const LibrarySnapshot({
    required this.systems,
    required this.games,
    required this.fromCache,
    required this.previousIds,
  });

  final List<SystemModel> systems;
  final List<GameSummary> games;
  final bool fromCache;

  /// Ids known before this refresh — used for the "what's new" hint.
  final Set<int> previousIds;
}

final librarySnapshotProvider = FutureProvider<LibrarySnapshot>((ref) async {
  final client = ref.watch(apiClientProvider);
  final cache = await ref.watch(libraryCacheProvider.future);
  final previous = await cache.load();
  final previousIds = <int>{
    for (final g in previous?.games ?? const <GameSummary>[]) g.id,
  };
  try {
    final systems = await client.fetchSystems();
    final games = <GameSummary>[];
    var page = 1;
    while (true) {
      final result = await client.fetchGames(page: page);
      games.addAll(result.results);
      if (!result.hasNext) break;
      page += 1;
    }
    await cache.save(systems, games);
    return LibrarySnapshot(
      systems: systems,
      games: games,
      fromCache: false,
      previousIds: previousIds,
    );
  } on DioException {
    if (previous == null) rethrow;
    return LibrarySnapshot(
      systems: previous.systems,
      games: previous.games,
      fromCache: true,
      previousIds: previousIds,
    );
  }
});

final isOfflineProvider = Provider<bool>(
  (ref) => ref.watch(librarySnapshotProvider).value?.fromCache ?? false,
);

final systemsProvider = FutureProvider<List<SystemModel>>(
  (ref) async => (await ref.watch(librarySnapshotProvider.future)).systems,
);

/// Riverpod 3 dropped StateProvider, so the two pieces of UI state are plain
/// notifiers with an explicit setter.
class SelectedSystem extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? code) => state = code;
}

final selectedSystemProvider =
    NotifierProvider<SelectedSystem, String?>(SelectedSystem.new);

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;
}

final searchQueryProvider =
    NotifierProvider<SearchQuery, String>(SearchQuery.new);

/// Client-side projection of the snapshot: the whole library of a single user
/// fits in memory, and filtering locally keeps offline mode working.
final gamesProvider = FutureProvider<List<GameSummary>>((ref) async {
  final snapshot = await ref.watch(librarySnapshotProvider.future);
  final system = ref.watch(selectedSystemProvider);
  final search = ref.watch(searchQueryProvider).trim().toLowerCase();
  return [
    for (final game in snapshot.games)
      if ((system == null || game.systemCode == system) &&
          (search.isEmpty || game.title.toLowerCase().contains(search)))
        game,
  ];
});
