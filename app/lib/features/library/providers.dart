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

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;
}

final searchQueryProvider =
    NotifierProvider<SearchQuery, String>(SearchQuery.new);

enum LibrarySort { title, recentlyAdded }

class SortOrder extends Notifier<LibrarySort> {
  @override
  LibrarySort build() => LibrarySort.title;

  void select(LibrarySort sort) => state = sort;
}

final sortProvider = NotifierProvider<SortOrder, LibrarySort>(SortOrder.new);

/// Zbiór id — jeden typ dla „na urządzeniu" i „do aktualizacji"; zasilany
/// przez odznaki na kafelkach, gdy rozwiążą stan lokalny.
class IdSet extends Notifier<Set<int>> {
  @override
  Set<int> build() => {};

  void mark(int id, {required bool installed}) {
    if (installed == state.contains(id)) return;
    final next = {...state};
    if (installed) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = next;
  }
}

final installedIdsProvider = NotifierProvider<IdSet, Set<int>>(IdSet.new);
final updatableIdsProvider = NotifierProvider<IdSet, Set<int>>(IdSet.new);

enum SystemFilter { all, installed, updatable }

class SystemFilterState extends Notifier<SystemFilter> {
  @override
  SystemFilter build() => SystemFilter.all;

  void select(SystemFilter filter) => state = filter;
}

final systemFilterProvider =
    NotifierProvider<SystemFilterState, SystemFilter>(SystemFilterState.new);

List<GameSummary> sortGames(List<GameSummary> games, LibrarySort sort) {
  final out = [...games];
  out.sort(
    switch (sort) {
      LibrarySort.title => (a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      LibrarySort.recentlyAdded => (a, b) => b.id.compareTo(a.id),
    },
  );
  return out;
}

List<GameSummary> applyFilter(
  List<GameSummary> games,
  SystemFilter filter,
  Set<int> installed,
  Set<int> updatable,
) =>
    switch (filter) {
      SystemFilter.all => games,
      SystemFilter.installed =>
        [for (final g in games) if (installed.contains(g.id)) g],
      SystemFilter.updatable =>
        [for (final g in games) if (updatable.contains(g.id)) g],
    };

class SystemShelf {
  const SystemShelf({required this.system, required this.games});

  final SystemModel system;
  final List<GameSummary> games;
}

class HomeShelves {
  const HomeShelves({
    required this.recent,
    required this.installed,
    required this.systems,
  });

  final List<GameSummary> recent;
  final List<GameSummary> installed;
  final List<SystemShelf> systems;
}

const kRecentShelfSize = 10;

HomeShelves buildShelves(
  List<GameSummary> games,
  List<SystemModel> systems,
  Set<int> installedIds,
  LibrarySort sort,
) {
  final recent =
      sortGames(games, LibrarySort.recentlyAdded).take(kRecentShelfSize);
  final installed = sortGames(
    [for (final g in games) if (installedIds.contains(g.id)) g],
    sort,
  );
  return HomeShelves(
    recent: recent.toList(),
    installed: installed,
    systems: [
      for (final system in systems)
        SystemShelf(
          system: system,
          games: sortGames(
            [for (final g in games) if (g.systemCode == system.code) g],
            sort,
          ),
        ),
    ],
  );
}

final homeShelvesProvider = FutureProvider<HomeShelves>((ref) async {
  final snapshot = await ref.watch(librarySnapshotProvider.future);
  return buildShelves(
    snapshot.games,
    snapshot.systems,
    ref.watch(installedIdsProvider),
    ref.watch(sortProvider),
  );
});

/// Gry jednego systemu po chipie filtra i sortowaniu.
final systemGamesProvider =
    FutureProvider.family<List<GameSummary>, String>((ref, code) async {
  final snapshot = await ref.watch(librarySnapshotProvider.future);
  final own = [for (final g in snapshot.games) if (g.systemCode == code) g];
  return sortGames(
    applyFilter(
      own,
      ref.watch(systemFilterProvider),
      ref.watch(installedIdsProvider),
      ref.watch(updatableIdsProvider),
    ),
    ref.watch(sortProvider),
  );
});

/// Wyniki szukajki po całej bibliotece (ekran główny).
final gamesProvider = FutureProvider<List<GameSummary>>((ref) async {
  final snapshot = await ref.watch(librarySnapshotProvider.future);
  final search = ref.watch(searchQueryProvider).trim().toLowerCase();
  return sortGames(
    [
      for (final g in snapshot.games)
        if (search.isEmpty || g.title.toLowerCase().contains(search)) g,
    ],
    ref.watch(sortProvider),
  );
});
