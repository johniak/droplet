import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/api/models.dart';
import 'game_tile.dart';

class GamesGrid extends StatelessWidget {
  const GamesGrid({
    super.key,
    required this.games,
    this.padding,
    this.routeFor,
  });

  final List<GameSummary> games;

  /// 16/12/16 by default, with bottom padding for the floating bar —
  /// computed from `MediaQuery`, so it resolves only in `build`.
  final EdgeInsets? padding;

  /// Route for a given id — `/game/<id>` by default. The system screen
  /// passes `(id) => '/system/<code>/game/<id>'` so the navigation stack goes
  /// back to the system list instead of the library.
  final String Function(int id)? routeFor;

  static const delegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    crossAxisSpacing: 14,
    mainAxisSpacing: 18,
    childAspectRatio: 0.58,
  );

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: padding ??
            EdgeInsets.fromLTRB(16, 12, 16, listBottomPad(context)),
        gridDelegate: delegate,
        itemCount: games.length,
        itemBuilder: (_, i) => GameTile(
          game: games[i],
          route: routeFor?.call(games[i].id),
        ),
      );
}
