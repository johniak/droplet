import 'package:droplet/core/api/models.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

GameSummary g(int id, String title, String system) => GameSummary(
      id: id,
      title: title,
      systemCode: system,
      hasCover: false,
      totalSize: 1,
    );

const systems = [
  SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 2),
  SystemModel(id: 2, code: 'psx', name: 'PSX', gameCount: 1),
  SystemModel(id: 3, code: 'gba', name: 'GBA', gameCount: 0),
];

void main() {
  final games = [
    for (var i = 1; i <= 12; i++) g(i, 'S$i', 'snes'),
    g(20, 'Tekken', 'psx'),
  ];

  test('buildShelves: recent, installed, per-system in API order', () {
    final shelves = buildShelves(games, systems, {3, 20}, LibrarySort.title);
    expect(shelves.recent.map((e) => e.id).take(3).toList(), [20, 12, 11]);
    expect(shelves.recent, hasLength(10));
    expect(shelves.installed.map((e) => e.title).toList(), ['S3', 'Tekken']);
    expect(shelves.systems.map((s) => s.system.code).toList(),
        ['snes', 'psx', 'gba']);
    expect(shelves.systems.first.games, hasLength(12));
    expect(shelves.systems.last.games, isEmpty);
  });

  test('IdSet marks and unmarks', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ids = container.read(updatableIdsProvider.notifier);
    ids.mark(1, installed: true);
    ids.mark(1, installed: true);
    expect(container.read(updatableIdsProvider), {1});
    ids.mark(1, installed: false);
    expect(container.read(updatableIdsProvider), isEmpty);
  });

  test('systemFilter provider selects', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(systemFilterProvider.notifier).select(SystemFilter.updatable);
    expect(container.read(systemFilterProvider), SystemFilter.updatable);
  });

  test('providers derive from the snapshot', () async {
    final container = ProviderContainer(
      overrides: [
        librarySnapshotProvider.overrideWith(
          (ref) async => LibrarySnapshot(
            systems: systems,
            games: games,
            fromCache: false,
            previousIds: const {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(installedIdsProvider.notifier).mark(3, installed: true);
    container.read(systemFilterProvider.notifier).select(SystemFilter.installed);
    expect(
      (await container.read(systemGamesProvider('snes').future)).single.id,
      3,
    );
    container.read(searchQueryProvider.notifier).update('tek');
    expect((await container.read(gamesProvider.future)).single.id, 20);
    final shelves = await container.read(homeShelvesProvider.future);
    expect(shelves.installed.single.id, 3);
  });
}
