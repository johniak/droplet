import 'package:background_downloader/background_downloader.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/downloads/task_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const file = GameFileModel(
    id: 42,
    name: 'Mario (USA).sfc',
    relativePath: 'snes/Mario (USA).sfc',
    role: FileRole.base,
    discNumber: null,
    version: '',
    size: 1024,
  );

  test('buildTask fills url, path, group and headers', () {
    final task = buildTask(
      serverUrl: 'http://nas:8000',
      authHeaders: {'Authorization': 'Token abc'},
      gameId: 7,
      file: file,
      settings: StorageSettings('/storage/emulated/0/RetroArch/roms', {}),
      systemCode: 'snes',
    );
    expect(task.url, 'http://nas:8000/api/files/42/download');
    expect(task.headers['Authorization'], 'Token abc');
    // background_downloader stores the directory relative to baseDirectory,
    // so the leading slash is stripped; BaseDirectory.root puts it back when
    // the task resolves its file path.
    expect(task.baseDirectory, BaseDirectory.root);
    expect(task.directory, 'storage/emulated/0/RetroArch/roms/snes');
    expect(task.filename, 'Mario (USA).sfc');
    expect(task.group, 'game-7');
    expect(task.allowPause, true);
    expect(gameIdOf(task), 7);
    expect(expectedSizeOf(task), 1024);
  });

  test('wifiOnly setting makes the task require Wi-Fi', () {
    final task = buildTask(
      serverUrl: 'http://nas:8000',
      authHeaders: const {'Authorization': 'Token t'},
      gameId: 7,
      file: file,
      settings: StorageSettings('/roms', const {}, wifiOnly: true),
      systemCode: 'snes',
    );
    expect(task.requiresWiFi, isTrue);
  });
}
