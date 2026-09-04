import 'package:flutter/material.dart';

import '../../../app/layout.dart';
import '../../../app/tokens.dart';
import '../../../core/api/models.dart';
import 'game_tile.dart';

class GamesGrid extends StatelessWidget {
  const GamesGrid({
    super.key,
    required this.games,
    this.padding,
    this.routeFor,
    this.autofocusFirst = false,
  });

  final List<GameSummary> games;

  /// The first tile takes the focus when the grid is what the screen opens
  /// on (the System screen, and Home's search results).
  final bool autofocusFirst;

  /// 16/12/16 by default, with bottom padding for the floating bar —
  /// computed from `MediaQuery`, so it resolves only in `build`.
  final EdgeInsets? padding;

  /// Route for a given id — `/game/<id>` by default. The system screen
  /// passes `(id) => '/system/<code>/game/<id>'` so the navigation stack goes
  /// back to the system list instead of the library.
  final String Function(int id)? routeFor;

  /// Columns follow the available width (about one per 200 dp, at least two),
  /// so a landscape handheld shows four tiles per row instead of two giants.
  static int columnsFor(double width) => (width / 200).floor().clamp(2, 8);

  /// Cell shape holds a cover plus room for two text lines.
  static SliverGridDelegate delegateFor(
    Iterable<String> systemCodes, {
    double width = 400,
  }) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnsFor(width),
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
        childAspectRatio:
            1 / (tallestCoverFactor(systemCodes) + kGridTextFactor),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => GridView.builder(
          padding: padding ??
              EdgeInsets.fromLTRB(16, 12, 16, listBottomPad(context)),
          gridDelegate: delegateFor(
            games.map((g) => g.systemCode),
            width: constraints.maxWidth,
          ),
          itemCount: games.length,
          itemBuilder: (_, i) => GameTile(
            game: games[i],
            route: routeFor?.call(games[i].id),
            autofocus: autofocusFirst && i == 0,
          ),
        ),
      );
}
