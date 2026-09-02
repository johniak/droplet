import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/game/providers.dart';
import '../api/models.dart';
import '../env.dart';
import '../platform/downloader_port.dart';
import '../platform/permissions_port.dart';
import 'local_state.dart';
import 'permissions.dart';
import 'storage_settings.dart';
import 'task_builder.dart';

class PermissionDeniedException implements Exception {
  @override
  String toString() => 'Brak dostępu do katalogu ROMów';
}

enum GameProgressStatus { running, paused, failed, complete }

class GameProgress {
  const GameProgress({
    required this.gameId,
    required this.title,
    required this.progress,
    required this.status,
  });

  final int gameId;
  final String title;
  final double progress;
  final GameProgressStatus status;

  GameProgress copyWith({double? progress, GameProgressStatus? status}) =>
      GameProgress(
        gameId: gameId,
        title: title,
        progress: progress ?? this.progress,
        status: status ?? this.status,
      );
}

class DownloadManager {
  DownloadManager(
    this._port,
    this._permissions, {
    required this.onGameChanged,
  }) {
    _subscription = _port.updates.listen(_onUpdate);
  }

  final DownloaderPort _port;
  final PermissionsPort _permissions;
  final void Function(int gameId) onGameChanged;

  late final StreamSubscription<TaskUpdate> _subscription;
  final _progress = <int, GameProgress>{};
  final _taskProgress = <String, double>{};
  final _tasksByGame = <int, List<DownloadTask>>{};
  final _controller = StreamController<Map<int, GameProgress>>.broadcast();
  bool _notificationsRequested = false;

  Map<int, GameProgress> get progress => Map.unmodifiable(_progress);

  Stream<Map<int, GameProgress>> get progressStream => _controller.stream;

  Future<void> dispose() async {
    await _subscription.cancel();
    await _controller.close();
  }

  Future<void> downloadGame({
    required GameDetail game,
    required Set<int> selectedIds,
    required LocalGameState local,
    required String serverUrl,
    required Map<String, String> authHeaders,
    required StorageSettings settings,
  }) async {
    if (!await ensureStoragePermission(_permissions, settings.baseDir)) {
      throw PermissionDeniedException();
    }
    if (!kE2E && !_notificationsRequested) {
      _notificationsRequested = true;
      await _port.ensureNotificationPermission();
    }
    final tasks = <DownloadTask>[];
    for (final file in game.files) {
      if (!selectedIds.contains(file.id)) continue;
      final target = settings.pathFor(game.systemCode, file.name);
      if (local.presentPaths.contains(target)) continue;
      tasks.add(
        buildTask(
          serverUrl: serverUrl,
          authHeaders: authHeaders,
          gameId: game.id,
          file: file,
          settings: settings,
          systemCode: game.systemCode,
        ),
      );
    }
    if (tasks.isEmpty) return;
    _tasksByGame[game.id] = tasks;
    _progress[game.id] = GameProgress(
      gameId: game.id,
      title: game.title,
      progress: 0,
      status: GameProgressStatus.running,
    );
    _emit();
    for (final task in tasks) {
      await _port.enqueue(task);
    }
  }

  Future<void> pauseGame(int gameId) async {
    for (final record in await _port.recordsForGroup('game-$gameId')) {
      await _port.pause(record.task as DownloadTask);
    }
  }

  Future<void> resumeGame(int gameId) async {
    for (final record in await _port.recordsForGroup('game-$gameId')) {
      await _port.resume(record.task as DownloadTask);
    }
  }

  Future<void> cancelGame(int gameId) async {
    for (final record in await _port.recordsForGroup('game-$gameId')) {
      await _port.cancel(record.task.taskId);
    }
    _progress.remove(gameId);
    _emit();
  }

  Future<void> retryGame(int gameId) async {
    for (final task in _tasksByGame[gameId] ?? const <DownloadTask>[]) {
      await _port.enqueue(task);
    }
    final current = _progress[gameId];
    if (current != null) {
      _progress[gameId] = current.copyWith(
        status: GameProgressStatus.running,
      );
      _emit();
    }
  }

  void _emit() => _controller.add(progress);

  void _onUpdate(TaskUpdate update) {
    final tasks = _tasksByGame.values.expand((t) => t);
    if (!tasks.any((t) => t.taskId == update.task.taskId)) return;
    final gameId = gameIdOf(update.task);
    if (update is TaskProgressUpdate) {
      _taskProgress[update.task.taskId] = update.progress;
      _recomputeProgress(gameId);
    } else if (update is TaskStatusUpdate) {
      unawaited(_onStatus(gameId, update));
    }
  }

  void _recomputeProgress(int gameId) {
    final tasks = _tasksByGame[gameId] ?? const <DownloadTask>[];
    var total = 0;
    var done = 0.0;
    for (final task in tasks) {
      final size = expectedSizeOf(task);
      total += size;
      done += size * (_taskProgress[task.taskId] ?? 0);
    }
    final current = _progress[gameId];
    if (current == null || total == 0) return;
    _progress[gameId] = current.copyWith(progress: done / total);
    _emit();
  }

  Future<void> _onStatus(int gameId, TaskStatusUpdate update) async {
    final current = _progress[gameId];
    if (current == null) return;
    switch (update.status) {
      case TaskStatus.paused:
        _progress[gameId] = current.copyWith(
          status: GameProgressStatus.paused,
        );
      case TaskStatus.failed:
      case TaskStatus.canceled:
      case TaskStatus.notFound:
        _progress[gameId] = current.copyWith(
          status: GameProgressStatus.failed,
        );
      case TaskStatus.complete:
        await _onComplete(gameId, update.task);
      case TaskStatus.enqueued:
      case TaskStatus.running:
      case TaskStatus.waitingToRetry:
        _progress[gameId] = current.copyWith(
          status: GameProgressStatus.running,
        );
    }
    _emit();
  }

  /// A finished file is only trusted when its size matches the manifest;
  /// otherwise it is deleted so a retry starts clean.
  Future<void> _onComplete(int gameId, Task task) async {
    final path = await _port.filePath(task);
    final actual = await _port.fileLength(path);
    final expected = expectedSizeOf(task);
    final current = _progress[gameId]!;
    if (actual != expected) {
      await _port.deleteFile(path);
      _progress[gameId] = current.copyWith(status: GameProgressStatus.failed);
    } else {
      _taskProgress[task.taskId] = 1;
      final tasks = _tasksByGame[gameId] ?? const <DownloadTask>[];
      final allDone = tasks.every((t) => (_taskProgress[t.taskId] ?? 0) >= 1);
      _progress[gameId] = current.copyWith(
        progress: allDone ? 1 : current.progress,
        status: allDone
            ? GameProgressStatus.complete
            : GameProgressStatus.running,
      );
    }
    onGameChanged(gameId);
  }
}

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final manager = DownloadManager(
    ref.watch(downloaderPortProvider),
    ref.watch(permissionsPortProvider),
    onGameChanged: (id) => ref.invalidate(localStateProvider(id)),
  );
  ref.onDispose(manager.dispose);
  return manager;
});
