import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../app/widgets/glass_panel.dart';
import '../../../core/api/models.dart';
import 'game_tile.dart';

class Shelf extends StatelessWidget {
  const Shelf({
    super.key,
    required this.title,
    required this.games,
    this.trailing,
    this.onSeeAll,
    this.cardWidth = 96,
    this.limit = 12,
  });

  final String title;
  final List<GameSummary> games;
  final String? trailing;
  final VoidCallback? onSeeAll;
  final double cardWidth;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final shown = games.take(limit).toList();
    final overflow = games.length > limit;
    final cardHeight = cardWidth * 4 / 3 + 26;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: kText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(color: kTextDim, fontSize: 13),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The whole header — title and "N ›" — is one tap target, so hitting
        // "Nintendo Switch" works just like hitting the counter.
        onSeeAll != null
            ? GestureDetector(
                onTap: onSeeAll,
                behavior: HitTestBehavior.opaque,
                child: header,
              )
            : header,
        SizedBox(
          height: cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: shown.length + (overflow ? 1 : 0),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: i < shown.length
                  ? ShelfCard(game: shown[i], width: cardWidth)
                  : SizedBox(
                      width: cardWidth,
                      child: GlassPanel(
                        onTap: onSeeAll,
                        padding: EdgeInsets.zero,
                        child: Center(
                          child: Text(
                            'All (${games.length})',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: kAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
