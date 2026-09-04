import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/library/providers.dart';
import '../api/models.dart';
import '../env.dart';
import '../platform/downloader_port.dart';
import '../platform/permissions_port.dart';
import 'local_state.dart';
import 'permissions.dart';
import 'space.dart';
import 'storage_settings.dart';
import 'task_builder.dart';

class PermissionDeniedException implements Exception {
  @override
  String toString() => 'No access to the ROM folder';
}

enum GameProgressStatus { running, paused, failed, complete }

class GameProgress {
  const GameProgress({
    required this.gameId,
    required this.title,
    required this.systemCode,
    required this.folder,
    required this.hasCover,
    required this.progress,
    required this.status,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.speedBytesPerSec,
  });

  final int gameId;
  final String title;
  final String systemCode;

  /// The game's folder in the ROM tree — the download tile builds a full
  /// [GameSummary] from it instead of substituting an empty string.
  final String folder;

  final bool hasCover;
  final double progress;
  final GameProgressStatus status;
  final int bytesDone;
  final int bytesTotal;

  /// null when the plugin does not know the speed (networkSpeed == -1).
  final int? speedBytesPerSec;

  int get bytesLeft => bytesTotal - bytesDone;

  /// [clearSpeed] forces [speedBytesPerSec] to null even though a plain
  /// `null` for [speedBytesPerSec] would otherwise mean "leave unchanged" —
  /// needed so a stalled/paused/failed download can drop a previously known
  /// speed instead of showing it forever.
  GameProgress copyWith({
    double? progress,
    GameProgressStatus? status,
    int? bytesDone,
    int? speedBytesPerSec,
    bool clearSpeed = false,
  }) =>
      GameProgress(
        gameId: gameId,
        title: title,
        systemCode: systemCode,
        folder: folder,
        hasCover: hasCover,
        progress: progress ?? this.progress,
        status: status ?? this.status,
        bytesDone: bytesDone ?? this.bytesDone,
        bytesTotal: bytesTotal,
        speedBytesPerSec:
            clearSpeed ? null : (speedBytesPerSec ?? this.speedBytesPerSec),
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
      final target =
          settings.pathFor(game.systemCode, game.folder, file.name);
      if (local.presentPaths.contains(target)) continue;
      tasks.add(
        buildTask(
          serverUrl: serverUrl,
          authHeaders: authHeaders,
          gameId: game.id,
          file: file,
          settings: settings,
          systemCode: game.systemCode,
          folder: game.folder,
        ),
      );
    }
    if (tasks.isEmpty) return;
    final needed = tasks.fold(0, (sum, t) => sum + expectedSizeOf(t));
    final free = await _port.freeBytes(settings.baseDir);
    if (!hasEnoughSpace(needed, free)) {
      throw InsufficientSpaceException(needed, free!);
    }
    _tasksByGame[game.id] = tasks;
    _progress[game.id] = GameProgress(
      gameId: game.id,
      title: game.title,
      systemCode: game.systemCode,
      folder: game.folder,
      hasCover: game.hasCover,
      progress: 0,
      status: GameProgressStatus.running,
      bytesTotal: needed,
    );
    _emit();
    for (final task in tasks) {
      await _port.enqueue(task);
    }
  }

  /// Every task of a game we can lay hands on: tracked database records,
  /// what the native queue reports right now, and what this manager enqueued
  /// itself — merged by task id. A download started before tracking was on
  /// (or in a previous app version) is still reachable through the last two.
  Future<List<DownloadTask>> _tasksOf(int gameId) async {
    final group = 'game-$gameId';
    final byId = <String, DownloadTask>{};
    for (final record in await _port.recordsForGroup(group)) {
      byId[record.taskId] = record.task as DownloadTask;
    }
    for (final task in await _port.liveTasksForGroup(group)) {
      byId.putIfAbsent(task.taskId, () => task as DownloadTask);
    }
    for (final task in _tasksByGame[gameId] ?? const <DownloadTask>[]) {
      byId.putIfAbsent(task.taskId, () => task);
    }
    return byId.values.toList();
  }

  Future<void> pauseGame(int gameId) async {
    for (final task in await _tasksOf(gameId)) {
      await _port.pause(task);
    }
  }

  Future<void> resumeGame(int gameId) async {
    for (final task in await _tasksOf(gameId)) {
      await _port.resume(task);
    }
  }

  Future<void> cancelGame(int gameId) async {
    for (final task in await _tasksOf(gameId)) {
      await _port.cancel(task.taskId);
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
      // background_downloader reports terminal states via negative progress
      // sentinels (-1 failed, -2 canceled, -3 notFound, -4 waitingToRetry,
      // -5 paused) alongside a TaskStatusUpdate; those aren't real byte
      // counts, so they must not feed the size-weighted progress math.
      if (update.progress < 0) return;
      _taskProgress[update.task.taskId] = update.progress;
      final knownSpeed = update.networkSpeed > 0;
      _recomputeProgress(
        gameId,
        speed:
            knownSpeed ? (update.networkSpeed * 1024 * 1024).round() : null,
        clearSpeed: !knownSpeed,
      );
    } else if (update is TaskStatusUpdate) {
      unawaited(_onStatus(gameId, update));
    }
  }

  void _recomputeProgress(int gameId, {int? speed, bool clearSpeed = false}) {
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
    _progress[gameId] = current.copyWith(
      progress: done / total,
      bytesDone: done.round(),
      speedBytesPerSec: speed,
      clearSpeed: clearSpeed,
    );
    _emit();
  }

  Future<void> _onStatus(int gameId, TaskStatusUpdate update) async {
    final current = _progress[gameId];
    if (current == null) return;
    switch (update.status) {
      case TaskStatus.paused:
        _progress[gameId] = current.copyWith(
          status: GameProgressStatus.paused,
          clearSpeed: true,
        );
      case TaskStatus.failed:
      case TaskStatus.canceled:
      case TaskStatus.notFound:
        _progress[gameId] = current.copyWith(
          status: GameProgressStatus.failed,
          clearSpeed: true,
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
      onGameChanged(gameId);
      return;
    }
    _taskProgress[task.taskId] = 1;
    final tasks = _tasksByGame[gameId] ?? const <DownloadTask>[];
    final allDone = tasks.every((t) => (_taskProgress[t.taskId] ?? 0) >= 1);
    _progress[gameId] = current.copyWith(
      progress: allDone ? 1 : current.progress,
      status:
          allDone ? GameProgressStatus.complete : GameProgressStatus.running,
      bytesDone: allDone ? current.bytesTotal : current.bytesDone,
    );
    // A disk scan costs a walk over the whole ROM tree, so it runs once per
    // game — after the last file (or after deleting a file of the wrong size),
    // not after every single downloaded file.
    if (allDone) onGameChanged(gameId);
  }

  /// Drops entries that finished successfully; failures stay for retry/cancel.
  void clearFinished() {
    _progress.removeWhere((_, p) => p.status == GameProgressStatus.complete);
    _emit();
  }
}

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  // Several games finishing in the same tick must trigger one disk scan, not
  // one per notification — hence the coalescing into a single task.
  var scheduled = false;
  var disposed = false;
  final manager = DownloadManager(
    ref.watch(downloaderPortProvider),
    ref.watch(permissionsPortProvider),
    onGameChanged: (_) {
      if (scheduled) return;
      scheduled = true;
      // A Timer, not a microtask: notifications for further games arrive from
      // behind the port's `await`s, so a microtask would already have run.
      Timer.run(() {
        scheduled = false;
        if (disposed) return;
        ref.read(deviceIndexProvider.notifier).refresh();
      });
    },
  );
  ref.onDispose(() {
    disposed = true;
    manager.dispose();
  });
  return manager;
});
