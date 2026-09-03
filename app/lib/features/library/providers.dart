import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/models.dart';
import '../../core/cache/library_cache.dart';
import '../../core/downloads/device_scan.dart';
import '../../core/downloads/local_state.dart';
import '../../core/downloads/storage_settings.dart';
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
    required this.manifest,
    required this.fromCache,
    required this.previousIds,
  });

  final List<SystemModel> systems;
  final List<GameSummary> games;

  /// Files of every game — the source of truth for comparing with disk.
  final List<ManifestEntry> manifest;

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
    final manifest = await client.fetchManifest();
    await cache.save(systems, games, manifest);
    return LibrarySnapshot(
      systems: systems,
      games: games,
      manifest: manifest,
      fromCache: false,
      previousIds: previousIds,
    );
  } on DioException {
    if (previous == null) rethrow;
    return LibrarySnapshot(
      systems: previous.systems,
      games: previous.games,
      manifest: previous.manifest,
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

/// The disk scan injected into the controller — this lets tests count how
/// many times the index really touched the disk.
typedef DeviceScanner = DeviceIndex Function(
  StorageSettings settings,
  Iterable<String> systemCodes,
  Set<String> knownFolderKeys,
);

/// One disk scan for the whole library: the state of every game in the
/// manifest, and along the way a list of files and folders it does not know.
class DeviceIndexController extends AsyncNotifier<Map<int, LocalGameState>> {
  DeviceIndexController({DeviceScanner? scan}) : _scan = scan ?? scanDevice;

  final DeviceScanner _scan;

  DeviceIndex _last = const DeviceIndex(games: {}, unknown: []);

  DeviceIndex get lastIndex => _last;

  /// The first `build` has finished (successfully or not) — only then may
  /// dependency changes call [refresh]; during `build` there is no state yet.
  bool _scanned = false;

  bool _disposed = false;

  /// `listen` instead of `watch`: a library or settings change must
  /// **recompute** the index, not invalidate the provider. An invalidated
  /// index rebuilds lazily — on the first read, and that read can land in the
  /// layout phase (a tab resubscribing after `TickerMode`). Derived providers
  /// (`installedIdsProvider` and friends) then invalidate mid-build and
  /// Riverpod blows up with
  /// "setState() or markNeedsBuild() called during build".
  @override
  Future<Map<int, LocalGameState>> build() async {
    _scanned = false;
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.listen(librarySnapshotProvider, (_, next) => _rescan(next));
    ref.listen(storageSettingsProvider, (_, next) => _rescan(next));
    LibrarySnapshot? usedSnapshot;
    StorageSettings? usedSettings;
    try {
      final snapshot = await ref.read(librarySnapshotProvider.future);
      usedSnapshot = snapshot;
      final settings = await ref.read(storageSettingsProvider.future);
      usedSettings = settings;
      return _compute(snapshot, settings);
    } finally {
      // `finally`, so also after an error: otherwise a failed first scan
      // (offline, empty cache) would block any recompute after every later,
      // successful snapshot.
      _scanned = true;
      // A change that arrived *during* the first scan had nobody to ask for
      // a recompute — the state did not exist yet. Comparing with what the
      // scan actually ran on tells such a change apart from a dependency
      // simply resolving (which happens on every start).
      if (!identical(ref.read(librarySnapshotProvider).value, usedSnapshot) ||
          !identical(ref.read(storageSettingsProvider).value, usedSettings)) {
        // A timer, not a microtask: a microtask from `finally` would run
        // before Riverpod assigns the state, and `state` would still be empty.
        Timer.run(() {
          if (!_disposed) refresh();
        });
      }
    }
  }

  /// One dependency invalidation means two notifications (first "loading",
  /// then data or error) — the scan must run once, on the second one, that is
  /// on current data.
  void _rescan(AsyncValue<Object?> next) {
    if (next.isLoading || !_scanned) return;
    refresh();
  }

  Map<int, LocalGameState> _compute(
    LibrarySnapshot snapshot,
    StorageSettings settings,
  ) {
    // Keyed by the resolved folder, not by the system code — see
    // [knownFolderKey]: two systems can share one subfolder.
    final known = {
      for (final e in snapshot.manifest)
        knownFolderKey(settings, e.systemCode, e.folder),
    };
    _last = _scan(
      settings,
      [for (final s in snapshot.systems) s.code],
      known,
    );
    return buildLocalStates(snapshot.manifest, _last, settings);
  }

  /// Rescan the disk after a download or a delete — no network.
  Future<void> refresh() async {
    final snapshot = ref.read(librarySnapshotProvider).value;
    final settings = ref.read(storageSettingsProvider).value;
    if (snapshot == null || settings == null) return;
    state = AsyncData(_compute(snapshot, settings));
  }
}

final deviceIndexProvider =
    AsyncNotifierProvider<DeviceIndexController, Map<int, LocalGameState>>(
  DeviceIndexController.new,
);

/// Files and folders in the ROM tree that no game in the manifest knows.
final unknownOnDeviceProvider = Provider<List<UnknownEntry>>((ref) {
  ref.watch(deviceIndexProvider); // recompute after every scan
  return ref.read(deviceIndexProvider.notifier).lastIndex.unknown;
});

Set<int> installedFrom(Map<int, LocalGameState> states) => {
      for (final e in states.entries)
        if (e.value.status != InstallStatus.none) e.key,
    };

Set<int> updatableFrom(Map<int, LocalGameState> states) => {
      for (final e in states.entries)
        if (e.value.updateAvailable) e.key,
    };

/// The sets widgets read. Providers **derived from providers** deliberately
/// stay out of other providers' chains (see `homeShelvesProvider`):
/// invalidating a link mid-chain can land in the build phase and topple
/// `UncontrolledProviderScope`.
final installedIdsProvider = Provider<Set<int>>(
  (ref) => installedFrom(ref.watch(deviceIndexProvider).value ?? const {}),
);

final updatableIdsProvider = Provider<Set<int>>(
  (ref) => updatableFrom(ref.watch(deviceIndexProvider).value ?? const {}),
);

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
    installedFrom(ref.watch(deviceIndexProvider).value ?? const {}),
    ref.watch(sortProvider),
  );
});

/// Games of one system after the filter chip and sorting.
final systemGamesProvider =
    FutureProvider.family<List<GameSummary>, String>((ref, code) async {
  final snapshot = await ref.watch(librarySnapshotProvider.future);
  final own = [for (final g in snapshot.games) if (g.systemCode == code) g];
  return sortGames(
    applyFilter(
      own,
      ref.watch(systemFilterProvider),
      installedFrom(ref.watch(deviceIndexProvider).value ?? const {}),
      updatableFrom(ref.watch(deviceIndexProvider).value ?? const {}),
    ),
    ref.watch(sortProvider),
  );
});

/// Search results across the whole library (home screen).
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
