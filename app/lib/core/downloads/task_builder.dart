import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';

import '../api/models.dart';
import 'storage_settings.dart';

DownloadTask buildTask({
  required String serverUrl,
  required Map<String, String> authHeaders,
  required int gameId,
  required GameFileModel file,
  required StorageSettings settings,
  required String systemCode,
}) =>
    DownloadTask(
      url: '$serverUrl/api/files/${file.id}/download',
      headers: authHeaders,
      // An absolute directory (with the leading '/') is what
      // background_downloader documents for BaseDirectory.root.
      baseDirectory: BaseDirectory.root,
      directory: settings.dirFor(systemCode),
      filename: file.name,
      group: 'game-$gameId',
      allowPause: true,
      retries: 3,
      updates: Updates.statusAndProgress,
      metaData: jsonEncode({'gameId': gameId, 'size': file.size}),
    );

Map<String, dynamic> _meta(Task task) =>
    jsonDecode(task.metaData) as Map<String, dynamic>;

int gameIdOf(Task task) => _meta(task)['gameId'] as int;

int expectedSizeOf(Task task) => _meta(task)['size'] as int;
