import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/downloads/local_state.dart';
import '../../../core/session/providers.dart';
import '../../game/providers.dart';
import '../providers.dart';
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'cover-${game.id}',
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
                  Positioned(
                    right: 6,
                    top: 6,
                    child: _InstallBadge(gameId: game.id),
                  ),
                ],
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


/// Corner badge telling at a glance whether the ROM is on the device.
class _InstallBadge extends ConsumerWidget {
  const _InstallBadge({required this.gameId});

  final int gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(localStateProvider(gameId)).value;
    if (local != null) {
      // Feed the "installed only" filter without a second disk scan.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref
            .read(installedIdsProvider.notifier)
            .mark(gameId, installed: local.status != InstallStatus.none),
      );
    }
    if (local == null || local.status == InstallStatus.none) {
      return const SizedBox.shrink();
    }
    final (icon, color) = switch ((local.status, local.updateAvailable)) {
      (_, true) => (Icons.arrow_circle_down, kAccent),
      (InstallStatus.installed, _) => (Icons.check_circle, kAccent),
      _ => (Icons.adjust, kTextDim),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kBg.withValues(alpha: 0.7),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}
