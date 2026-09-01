import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/session/providers.dart';
import 'cover_image.dart';

class GameCard extends ConsumerWidget {
  const GameCard({super.key, required this.game});

  final GameSummary game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only a game that actually has a cover needs the API client, so a
    // cover-less grid renders without a session (and without HTTP).
    final client = game.hasCover ? ref.watch(apiClientProvider) : null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.go('/game/${game.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: CoverImage(
                  title: game.title,
                  url: client?.coverUrl(game.id) ?? '',
                  headers: client?.authHeaders ?? const {},
                  hasCover: game.hasCover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            game.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: kText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
