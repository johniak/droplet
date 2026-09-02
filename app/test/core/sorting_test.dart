import 'package:droplet/core/api/models.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter_test/flutter_test.dart';

GameSummary g(int id, String title, [String system = 'x']) => GameSummary(
      id: id,
      title: title,
      systemCode: system,
      hasCover: false,
      totalSize: 1,
      folder: title,
    );

void main() {
  final games = [g(1, 'Zelda'), g(3, 'Aero'), g(2, 'Mario')];

  test('title sort', () {
    expect(
      sortGames(games, LibrarySort.title).map((e) => e.title).toList(),
      ['Aero', 'Mario', 'Zelda'],
    );
  });

  test('recently added sort', () {
    expect(
      sortGames(games, LibrarySort.recentlyAdded).map((e) => e.id).toList(),
      [3, 2, 1],
    );
  });

  test('filters: all / installed / updatable', () {
    expect(applyFilter(games, SystemFilter.all, {}, {}), hasLength(3));
    expect(
      applyFilter(games, SystemFilter.installed, {2}, {}).single.title,
      'Mario',
    );
    expect(
      applyFilter(games, SystemFilter.updatable, {2}, {3}).single.title,
      'Aero',
    );
  });
}
