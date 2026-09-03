import 'package:droplet/app/layout.dart';
import 'package:droplet/features/library/widgets/games_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Switch covers are square, everything else is portrait boxart', () {
    expect(coverAspectRatio('switch'), 1);
    expect(coverAspectRatio('snes'), 3 / 4);
    expect(coverAspectRatio(''), 3 / 4);
  });

  test('tallest cover factor follows the tallest system in the list', () {
    expect(tallestCoverFactor(const []), 4 / 3);
    expect(tallestCoverFactor(const ['switch']), 1);
    expect(tallestCoverFactor(const ['switch', 'snes']), 4 / 3);
  });

  test('grid cells shrink for a Switch-only list', () {
    double ratio(Iterable<String> codes) =>
        (GamesGrid.delegateFor(codes) as SliverGridDelegateWithFixedCrossAxisCount)
            .childAspectRatio;
    expect(ratio(const ['snes']), closeTo(0.58, 1e-9));
    expect(ratio(const []), closeTo(0.58, 1e-9));
    expect(ratio(const ['switch']), closeTo(1 / (1 + kGridTextFactor), 1e-9));
    expect(ratio(const ['switch']), greaterThan(0.58));
  });

  test('wide layout breakpoint', () {
    expect(isWideWidth(599), isFalse);
    expect(isWideWidth(600), isTrue);
  });
}
