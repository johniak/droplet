// coverage:ignore-file
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thin adapter over background_downloader; the queue logic lives in
/// `lib/core/downloads/download_manager.dart` and runs on fakes in tests.
abstract class DownloaderPort {
  Stream<TaskUpdate> get updates;
  Future<bool> enqueue(DownloadTask task);
  Future<bool> pause(DownloadTask task);
  Future<bool> resume(DownloadTask task);
  Future<bool> cancel(String taskId);
  Future<List<TaskRecord>> allRecords();
  Future<List<TaskRecord>> recordsForGroup(String group);
  Future<String> filePath(Task task);
  Future<int?> fileLength(String path);
  Future<void> deleteFile(String path);
  Future<void> ensureNotificationPermission();

  /// Free bytes on the volume holding [path]; null when unknown.
  Future<int?> freeBytes(String path);
}

/// `FileDownloader().updates` is a single-subscription stream, so it is turned
/// into a broadcast stream once per isolate — otherwise a second
/// DownloadManager (another ProviderContainer, e.g. in tests) throws.
final _updates = FileDownloader().updates.asBroadcastStream();

class BackgroundDownloaderPort implements DownloaderPort {
  const BackgroundDownloaderPort();

  @override
  Stream<TaskUpdate> get updates => _updates;

  @override
  Future<bool> enqueue(DownloadTask task) => FileDownloader().enqueue(task);

  @override
  Future<bool> pause(DownloadTask task) => FileDownloader().pause(task);

  @override
  Future<bool> resume(DownloadTask task) => FileDownloader().resume(task);

  @override
  Future<bool> cancel(String taskId) =>
      FileDownloader().cancelTaskWithId(taskId);

  @override
  Future<List<TaskRecord>> allRecords() => FileDownloader().database.allRecords();

  @override
  Future<List<TaskRecord>> recordsForGroup(String group) =>
      FileDownloader().database.allRecords(group: group);

  @override
  Future<String> filePath(Task task) => task.filePath();

  @override
  Future<int?> fileLength(String path) async {
    final file = File(path);
    return await file.exists() ? file.length() : null;
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> ensureNotificationPermission() async {
    await FileDownloader().permissions.request(PermissionType.notifications);
  }

  @override
  Future<int?> freeBytes(String path) async {
    try {
      final stat = await Process.run('df', ['-k', path]);
      final line = (stat.stdout as String).trim().split('\n').last;
      final columns = line.split(RegExp(r'\s+'));
      return int.parse(columns[3]) * 1024;
    } catch (_) {
      return null;
    }
  }
}

final downloaderPortProvider = Provider<DownloaderPort>(
  (ref) => const BackgroundDownloaderPort(),
);
