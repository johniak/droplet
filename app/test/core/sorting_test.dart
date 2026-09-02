import 'package:droplet/core/api/models.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter_test/flutter_test.dart';

GameSummary g(int id, String title) => GameSummary(
      id: id,
      title: title,
      systemCode: 'x',
      hasCover: false,
      totalSize: 1,
    );

void main() {
  final games = [g(1, 'Zelda'), g(3, 'Aero'), g(2, 'Mario')];

  test('title sort', () {
    final out = sortAndFilter(games, LibrarySort.title, false, {});
    expect(out.map((e) => e.title).toList(), ['Aero', 'Mario', 'Zelda']);
  });

  test('recently added sort', () {
    final out = sortAndFilter(games, LibrarySort.recentlyAdded, false, {});
    expect(out.map((e) => e.id).toList(), [3, 2, 1]);
  });

  test('installed only filter', () {
    final out = sortAndFilter(games, LibrarySort.title, true, {2});
    expect(out.single.title, 'Mario');
  });
}
