import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/tokens.dart';
import '../../../core/downloads/local_state.dart';
import '../../game/providers.dart';
import '../providers.dart';

/// Odznaka w rogu okładki; przy okazji zasila zbiory id dla filtrów.
class InstallBadge extends ConsumerWidget {
  const InstallBadge({super.key, required this.gameId});

  final int gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(localStateProvider(gameId)).value;
    if (local != null) {
      // Notatniki czytamy teraz, przed zaplanowaniem callbacku — po klatce
      // ten widget mógł już zniknąć z drzewa (np. wyjechał z Shelf), a
      // wtedy `ref.read` rzuca StateError na odpiętym elemencie.
      final installedNotifier = ref.read(installedIdsProvider.notifier);
      final updatableNotifier = ref.read(updatableIdsProvider.notifier);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        installedNotifier.mark(
          gameId,
          installed: local.status != InstallStatus.none,
        );
        updatableNotifier.mark(gameId, installed: local.updateAvailable);
      });
    }
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
