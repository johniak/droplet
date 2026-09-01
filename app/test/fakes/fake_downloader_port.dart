import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:droplet/core/platform/downloader_port.dart';

class FakeDownloaderPort implements DownloaderPort {
  final controller = StreamController<TaskUpdate>.broadcast();
  final enqueued = <DownloadTask>[];
  final deleted = <String>[];
  final lengths = <String, int?>{};
  int notificationRequests = 0;
  final paused = <String>[];
  final resumed = <String>[];
  final cancelled = <String>[];

  @override
  Stream<TaskUpdate> get updates => controller.stream;

  @override
  Future<bool> enqueue(DownloadTask task) async {
    enqueued.add(task);
    return true;
  }

  @override
  Future<bool> pause(DownloadTask task) async {
    paused.add(task.taskId);
    return true;
  }

  @override
  Future<bool> resume(DownloadTask task) async {
    resumed.add(task.taskId);
    return true;
  }

  @override
  Future<bool> cancel(String taskId) async {
    cancelled.add(taskId);
    return true;
  }

  @override
  Future<List<TaskRecord>> allRecords() async => [];

  @override
  Future<List<TaskRecord>> recordsForGroup(String group) async => [
        for (final t in enqueued.where((t) => t.group == group))
          TaskRecord(t, TaskStatus.running, 0.5, 1024),
      ];

  // Mirrors Task.filePath() for BaseDirectory.root: the plugin stores the
  // directory without the leading slash and puts it back when resolving.
  @override
  Future<String> filePath(Task task) async =>
      '/${task.directory}/${task.filename}';

  @override
  Future<int?> fileLength(String path) async => lengths[path];

  @override
  Future<void> deleteFile(String path) async => deleted.add(path);

  @override
  Future<void> ensureNotificationPermission() async => notificationRequests++;
}
