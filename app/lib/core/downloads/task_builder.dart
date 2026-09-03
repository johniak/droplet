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
  required String folder,
}) {
  // `file.name` is relative to the game folder, so it can carry a subfolder
  // (e.g. `disc1/FF7 (Disc 1).bin`) — the plugin wants it in `directory`.
  final slash = file.name.lastIndexOf('/');
  final sub = slash < 0 ? '' : '/${file.name.substring(0, slash)}';
  final base = slash < 0 ? file.name : file.name.substring(slash + 1);
  return DownloadTask(
    url: '$serverUrl/api/files/${file.id}/download',
    headers: authHeaders,
    // An absolute directory (with the leading '/') is what
    // background_downloader documents for BaseDirectory.root.
    baseDirectory: BaseDirectory.root,
    directory: '${settings.gameDir(systemCode, folder)}$sub',
    filename: base,
    group: 'game-$gameId',
    allowPause: true,
    retries: 3,
    requiresWiFi: settings.wifiOnly,
    updates: Updates.statusAndProgress,
    metaData: jsonEncode({'gameId': gameId, 'size': file.size}),
  );
}

Map<String, dynamic> _meta(Task task) =>
    jsonDecode(task.metaData) as Map<String, dynamic>;

int gameIdOf(Task task) => _meta(task)['gameId'] as int;

int expectedSizeOf(Task task) => _meta(task)['size'] as int;
