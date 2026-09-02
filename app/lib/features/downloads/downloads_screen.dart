import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/downloads/download_manager.dart';

final _progressStreamProvider = StreamProvider<Map<int, GameProgress>>(
  (ref) => ref.watch(downloadManagerProvider).progressStream,
);

final activeDownloadsProvider = Provider<List<GameProgress>>((ref) {
  final live = ref.watch(_progressStreamProvider).value;
  final current = live ?? ref.watch(downloadManagerProvider).progress;
  return current.values.toList();
});

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeDownloadsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pobierania')),
      body: active.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: active.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _DownloadRow(progress: active[i]),
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Brak aktywnych pobierań',
                style: TextStyle(color: kText, fontSize: 17),
              ),
              SizedBox(height: 8),
              Text(
                'Wybierz grę i naciśnij Pobierz.',
                style: TextStyle(color: kTextDim),
              ),
            ],
          ),
        ),
      );
}

class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({required this.progress});

  final GameProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(downloadManagerProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kText, fontSize: 15),
                ),
              ),
              ..._actionsFor(manager),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress.progress,
            backgroundColor: kSurface,
            color: progress.status == GameProgressStatus.failed
                ? const Color(0xFFF07178)
                : kAccent,
          ),
        ],
      ),
    );
  }

  List<Widget> _actionsFor(DownloadManager manager) => switch (progress.status) {
        GameProgressStatus.running => [
            IconButton(
              icon: const Icon(Icons.pause, color: kTextDim),
              tooltip: 'Wstrzymaj',
              onPressed: () => manager.pauseGame(progress.gameId),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: kTextDim),
              tooltip: 'Anuluj',
              onPressed: () => manager.cancelGame(progress.gameId),
            ),
          ],
        GameProgressStatus.paused => [
            IconButton(
              icon: const Icon(Icons.play_arrow, color: kTextDim),
              tooltip: 'Wznów',
              onPressed: () => manager.resumeGame(progress.gameId),
            ),
          ],
        GameProgressStatus.failed => [
            TextButton(
              onPressed: () => manager.retryGame(progress.gameId),
              child: const Text('Ponów'),
            ),
          ],
        GameProgressStatus.complete => const [
            Icon(Icons.check_circle, color: kAccent),
          ],
      };
}
