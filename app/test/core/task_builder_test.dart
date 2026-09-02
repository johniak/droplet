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
      folder: 'Mario (USA)',
    );
    expect(task.url, 'http://nas:8000/api/files/42/download');
    expect(task.headers['Authorization'], 'Token abc');
    // background_downloader stores the directory relative to baseDirectory,
    // so the leading slash is stripped; BaseDirectory.root puts it back when
    // the task resolves its file path.
    expect(task.baseDirectory, BaseDirectory.root);
    expect(
      task.directory,
      'storage/emulated/0/RetroArch/roms/snes/Mario (USA)',
    );
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
      folder: 'Mario (USA)',
    );
    expect(task.requiresWiFi, isTrue);
  });

  test('a name with a subdirectory splits into directory and filename', () {
    final task = buildTask(
      serverUrl: 'http://nas:8000',
      authHeaders: const {},
      gameId: 7,
      file: const GameFileModel(
        id: 43,
        name: 'disc1/a.bin',
        relativePath: '',
        role: FileRole.disc,
        discNumber: 1,
        version: '',
        size: 8,
      ),
      settings: StorageSettings('/storage/emulated/0/RetroArch/roms', const {}),
      systemCode: 'snes',
      folder: 'Mario (USA)',
    );
    expect(task.directory, endsWith('/Mario (USA)/disc1'));
    expect(task.filename, 'a.bin');
  });
}
