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

  /// Domyślnie 16/12/16 z dolnym marginesem spod pływającego paska —
  /// liczonym z `MediaQuery`, więc rozwiązywanym dopiero w `build`.
  final EdgeInsets? padding;

  /// Trasa dla danego id — domyślnie `/game/<id>`. Ekran systemu (kolejny
  /// task) podaje `(id) => '/system/<code>/game/<id>'`, żeby stos nawigacji
  /// wracał do listy systemu zamiast do biblioteki.
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
