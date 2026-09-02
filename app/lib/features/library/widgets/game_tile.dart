import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/api/models.dart';
import '../../../core/format.dart';
import '../../../core/session/providers.dart';
import 'cover_image.dart';
import 'install_badge.dart';

/// Okładka 3:4 z odznaką — wspólny kawałek kafla gridu i kafla półki.
class CoverThumb extends ConsumerWidget {
  const CoverThumb({
    super.key,
    required this.game,
    this.hero = false,
    this.showBadge = true,
  });

  final GameSummary game;
  final bool hero;

  /// Kafelek pobierania ma własny stan i 40 px szerokości — odznaka „na
  /// urządzeniu" byłaby tam nieczytelna i myląca, więc da się ją wyłączyć.
  final bool showBadge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tylko gra z okładką potrzebuje klienta — grid bez okładek nie strzela
    // po HTTP i nie wymaga sesji w testach.
    final client = game.hasCover ? ref.watch(apiClientProvider) : null;
    Widget image = CoverImage(
      title: game.title,
      url: client?.coverUrl(game.id) ?? '',
      headers: client?.authHeaders ?? const {},
      hasCover: game.hasCover,
    );
    if (hero) image = Hero(tag: 'cover-${game.id}', child: image);
    return ClipRRect(
      borderRadius: BorderRadius.circular(kRadiusCover),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: kGlassBorder),
                borderRadius: BorderRadius.circular(kRadiusCover),
              ),
              position: DecorationPosition.foreground,
              child: image,
            ),
            if (showBadge)
              Positioned(
                right: 6,
                top: 6,
                child: InstallBadge(gameId: game.id),
              ),
          ],
        ),
      ),
    );
  }
}

class GameTile extends StatelessWidget {
  const GameTile({super.key, required this.game, this.hero = true, this.route});

  final GameSummary game;
  final bool hero;

  /// Trasa docelowa po dotknięciu — domyślnie `/game/{id}`, ale ekran
  /// systemu (kolejny task) podaje `/system/<code>/game/<id>`, żeby stos
  /// nawigacji wracał do listy systemu.
  final String? route;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(kRadiusCover),
        onTap: () => context.go(route ?? '/game/${game.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverThumb(game: game, hero: hero),
            const SizedBox(height: 8),
            Text(
              game.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatBytes(game.totalSize),
              style: const TextStyle(color: kTextDim, fontSize: 12),
            ),
          ],
        ),
      );
}

class ShelfCard extends StatelessWidget {
  const ShelfCard({super.key, required this.game, this.width = 96});

  final GameSummary game;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusCover),
          onTap: () => context.go('/game/${game.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverThumb(game: game),
              const SizedBox(height: 6),
              Text(
                game.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: kText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}
