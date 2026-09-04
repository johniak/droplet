import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../app/widgets/circle_icon_button.dart';
import '../../app/widgets/glass_panel.dart';
import '../../app/widgets/section_label.dart';
import '../../core/api/models.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/format.dart';
import '../library/widgets/game_tile.dart';
import 'providers.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(activeDownloadsProvider);
    final active = all.where(isActive).toList();
    final finished = all.where((p) => !isActive(p)).toList();
    final left = active.fold(0, (sum, p) => sum + p.bytesLeft);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 10, 16, listBottomPad(context)),
          children: [
            const Text(
              'Downloads',
              style: TextStyle(
                color: kText,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
            Text(
              active.isEmpty
                  ? 'Nothing active'
                  : '${active.length} active · ${formatBytes(left)} left',
              style: const TextStyle(color: kTextDim, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (all.isEmpty) const _Empty(),
            for (var i = 0; i < active.length; i++)
              _DownloadCard(progress: active[i], autofocus: i == 0),
            if (finished.isNotEmpty) ...[
              SectionLabel(
                'Finished',
                trailing: 'Clear',
                onTrailingTap: () =>
                    ref.read(downloadManagerProvider).clearFinished(),
              ),
              for (var i = 0; i < finished.length; i++)
                _DownloadCard(
                  progress: finished[i],
                  autofocus: active.isEmpty && i == 0,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Icon(Icons.download_rounded, size: 40, color: kTextDim),
            SizedBox(height: 12),
            Text('No downloads', style: TextStyle(color: kText, fontSize: 17)),
            SizedBox(height: 6),
            Text(
              'Pick a game and tap Download.',
              style: TextStyle(color: kTextDim),
            ),
          ],
        ),
      );
}

class _DownloadCard extends ConsumerWidget {
  const _DownloadCard({required this.progress, this.autofocus = false});

  final GameProgress progress;

  /// The topmost row — where the pad lands when the tab opens.
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(downloadManagerProvider);
    final failed = progress.status == GameProgressStatus.failed;
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      autofocus: autofocus,
      onTap: () => context.go('/game/${progress.gameId}'),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: CoverThumb(
              showBadge: false,
              game: GameSummary(
                id: progress.gameId,
                title: progress.title,
                systemCode: progress.systemCode,
                hasCover: progress.hasCover,
                totalSize: progress.bytesTotal,
                folder: progress.folder,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  progress.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  progressSubtitle(progress),
                  style: TextStyle(
                    color: failed ? kDanger : kTextDim,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.progress,
                    minHeight: 5,
                    backgroundColor: kGlass,
                    color: failed ? kDanger : kAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ..._actions(manager),
        ],
      ),
    );
  }

  List<Widget> _actions(DownloadManager manager) => switch (progress.status) {
        GameProgressStatus.running => [
            CircleIconButton(
              icon: Icons.pause_rounded,
              tooltip: 'Pause',
              onPressed: () => manager.pauseGame(progress.gameId),
            ),
            const SizedBox(width: 6),
            _cancelButton(manager),
          ],
        GameProgressStatus.paused => [
            CircleIconButton(
              icon: Icons.play_arrow_rounded,
              tooltip: 'Resume',
              onPressed: () => manager.resumeGame(progress.gameId),
            ),
            const SizedBox(width: 6),
            _cancelButton(manager),
          ],
        // A failed download must stay dismissable, not just retryable.
        GameProgressStatus.failed => [
            CircleIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Retry',
              onPressed: () => manager.retryGame(progress.gameId),
            ),
            const SizedBox(width: 6),
            _cancelButton(manager),
          ],
        GameProgressStatus.complete => const [
            Icon(Icons.check_circle_rounded, color: kAccent),
          ],
      };

  CircleIconButton _cancelButton(DownloadManager manager) => CircleIconButton(
        icon: Icons.close_rounded,
        tooltip: 'Cancel',
        onPressed: () => manager.cancelGame(progress.gameId),
      );
}
