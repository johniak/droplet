import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/tokens.dart';
import '../../../core/downloads/local_state.dart';
import '../../../core/downloads/download_manager.dart';
import '../../downloads/providers.dart';
import '../../game/providers.dart';

/// Badge in the corner of a cover — a pure read from the device index.
class InstallBadge extends ConsumerWidget {
  const InstallBadge({super.key, required this.gameId});

  final int gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A download in flight wins over the on-disk state: the ring fills as
    // the bytes arrive, dimmed while paused, red when it failed.
    final transfer = ref
        .watch(activeDownloadsProvider)
        .where((p) => p.gameId == gameId && p.status != GameProgressStatus.complete)
        .firstOrNull;
    if (transfer != null) {
      final color = switch (transfer.status) {
        GameProgressStatus.failed => kDanger,
        GameProgressStatus.paused => kTextDim,
        _ => kAccent,
      };
      return Container(
        key: const Key('badge-progress'),
        width: 22,
        height: 22,
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(color: kBgBottom, shape: BoxShape.circle),
        child: CircularProgressIndicator(
          value: transfer.status == GameProgressStatus.failed
              ? 1
              : transfer.progress.clamp(0.0, 1.0),
          strokeWidth: 2.5,
          color: color,
          backgroundColor: kGlassBorder,
        ),
      );
    }
    final local = ref.watch(localStateProvider(gameId)).value;
    if (local == null || local.status == InstallStatus.none) {
      return const SizedBox.shrink();
    }
    final (icon, bg, fg) = switch ((local.status, local.updateAvailable)) {
      (_, true) => (Icons.arrow_downward_rounded, kBgBottom, kAccent),
      (InstallStatus.installed, _) => (Icons.check_rounded, kAccent, kBgBottom),
      _ => (Icons.more_horiz_rounded, kBgBottom, kTextDim),
    };
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: fg.withValues(alpha: 0.6)),
      ),
      child: Icon(icon, size: 14, color: fg),
    );
  }
}
