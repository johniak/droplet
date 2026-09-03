import 'package:droplet/app/layout.dart';
import 'package:droplet/features/library/widgets/games_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every cover is square, whatever the system', () {
    expect(coverAspectRatio('switch'), 1);
    expect(coverAspectRatio('snes'), 1);
    expect(tallestCoverFactor(const []), 1);
    expect(tallestCoverFactor(const ['switch', 'snes']), 1);
  });

  test('grid cells hold a square cover plus two text lines', () {
    double ratio(Iterable<String> codes) =>
        (GamesGrid.delegateFor(codes) as SliverGridDelegateWithFixedCrossAxisCount)
            .childAspectRatio;
    expect(ratio(const ['snes']), closeTo(1 / (1 + kGridTextFactor), 1e-9));
    expect(ratio(const []), closeTo(1 / (1 + kGridTextFactor), 1e-9));
  });

  test('grid columns follow the width, at least two', () {
    expect(GamesGrid.columnsFor(360), 2);
    expect(GamesGrid.columnsFor(400), 2);
    expect(GamesGrid.columnsFor(600), 3);
    expect(GamesGrid.columnsFor(914), 4);
    expect(GamesGrid.columnsFor(5000), 8);
    final d = GamesGrid.delegateFor(const ['snes'], width: 914)
        as SliverGridDelegateWithFixedCrossAxisCount;
    expect(d.crossAxisCount, 4);
  });

  test('wide layout breakpoint', () {
    expect(isWideWidth(599), isFalse);
    expect(isWideWidth(600), isTrue);
  });
}
