import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/downloads/download_manager.dart';
import '../../core/format.dart';

final _progressStreamProvider = StreamProvider<Map<int, GameProgress>>(
  (ref) => ref.watch(downloadManagerProvider).progressStream,
);

/// All manager entries (active and finished), in the order they were added.
final activeDownloadsProvider = Provider<List<GameProgress>>((ref) {
  final live = ref.watch(_progressStreamProvider).value;
  final current = live ?? ref.watch(downloadManagerProvider).progress;
  return current.values.toList();
});

bool isActive(GameProgress p) =>
    p.status == GameProgressStatus.running ||
    p.status == GameProgressStatus.paused;

final activeCountProvider = Provider<int>(
  (ref) => ref.watch(activeDownloadsProvider).where(isActive).length,
);

String progressSubtitle(GameProgress p) {
  final bytes = '${formatBytes(p.bytesDone)} / ${formatBytes(p.bytesTotal)}';
  return switch (p.status) {
    GameProgressStatus.running => p.speedBytesPerSec == null
        ? bytes
        : '$bytes · ${formatBytes(p.speedBytesPerSec!)}/s',
    GameProgressStatus.paused => 'Paused · $bytes',
    GameProgressStatus.failed => 'Download failed — retry',
    GameProgressStatus.complete => 'Done · ${formatBytes(p.bytesTotal)}',
  };
}
