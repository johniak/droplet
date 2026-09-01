import 'package:background_downloader/background_downloader.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/download_manager.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/env.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/core/platform/permissions_port.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_permissions_port.dart';

void main() {
  const file = GameFileModel(
    id: 42,
    name: 'm.sfc',
    relativePath: 'snes/m.sfc',
    role: FileRole.base,
    discNumber: null,
    version: '',
    size: 1024,
  );
  const game = GameDetail(
    id: 7,
    title: 'Mario',
    systemCode: 'snes',
    systemName: 'SNES',
    hasCover: false,
    totalSize: 1024,
    files: [file],
  );
  final settings = StorageSettings('/roms', {});
  const none = LocalGameState(
    status: InstallStatus.none,
    updateAvailable: false,
    missing: [file],
    presentPaths: [],
  );

  late FakeDownloaderPort port;
  late FakePermissionsPort perms;
  late List<int> changed;
  late DownloadManager manager;

  setUp(() {
    port = FakeDownloaderPort();
    perms = FakePermissionsPort(granted: true);
    changed = [];
    manager = DownloadManager(port, perms, onGameChanged: changed.add);
  });

  tearDown(() => manager.dispose());

  Future<void> start([LocalGameState local = none]) => manager.downloadGame(
        game: game,
        selectedIds: {42},
        local: local,
        serverUrl: 'http://nas:8000',
        authHeaders: const {'Authorization': 'Token t'},
        settings: settings,
      );

  test('enqueues selected, missing files', () async {
    await start();
    expect(port.enqueued.single.url, 'http://nas:8000/api/files/42/download');
    expect(manager.progress[7]?.status, GameProgressStatus.running);
  });

  test('skips files already present', () async {
    await start(
      const LocalGameState(
        status: InstallStatus.installed,
        updateAvailable: false,
        missing: [],
        presentPaths: ['/roms/snes/m.sfc'],
      ),
    );
    expect(port.enqueued, isEmpty);
  });

  test('denied permission throws and enqueues nothing', () async {
    perms.granted = false;
    manager = DownloadManager(port, perms, onGameChanged: changed.add);
    await expectLater(start(), throwsA(isA<PermissionDeniedException>()));
    expect(port.enqueued, isEmpty);
  });

  test('progress updates are size-weighted', () async {
    await start();
    port.controller.add(TaskProgressUpdate(port.enqueued.single, 0.25));
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[7]?.progress, closeTo(0.25, 0.001));
  });

  test('complete with matching size -> complete + onGameChanged', () async {
    await start();
    port.lengths['/roms/snes/m.sfc'] = 1024;
    port.controller.add(
      TaskStatusUpdate(port.enqueued.single, TaskStatus.complete),
    );
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[7]?.status, GameProgressStatus.complete);
    expect(changed, [7]);
    expect(port.deleted, isEmpty);
  });

  test('complete with size mismatch -> file deleted, failed', () async {
    await start();
    port.lengths['/roms/snes/m.sfc'] = 10;
    port.controller.add(
      TaskStatusUpdate(port.enqueued.single, TaskStatus.complete),
    );
    await Future<void>.delayed(Duration.zero);
    expect(port.deleted, ['/roms/snes/m.sfc']);
    expect(manager.progress[7]?.status, GameProgressStatus.failed);
  });

  test('failed/paused statuses map to progress status', () async {
    await start();
    port.controller.add(
      TaskStatusUpdate(port.enqueued.single, TaskStatus.paused),
    );
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[7]?.status, GameProgressStatus.paused);
    port.controller.add(
      TaskStatusUpdate(port.enqueued.single, TaskStatus.failed),
    );
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[7]?.status, GameProgressStatus.failed);
  });

  test('pause/resume/cancel/retry act on the game group', () async {
    await start();
    await manager.pauseGame(7);
    await manager.resumeGame(7);
    await manager.cancelGame(7);
    expect(port.paused.length + port.resumed.length + port.cancelled.length, 3);
    await manager.retryGame(7);
    expect(port.enqueued.length, 2);
  });

  test('notification permission requested once (not in e2e)', () async {
    await start();
    await start();
    expect(port.notificationRequests, kE2E ? 0 : 1);
  });

  test('progressStream emits on every change', () async {
    final seen = <Map<int, GameProgress>>[];
    final sub = manager.progressStream.listen(seen.add);
    addTearDown(sub.cancel);
    await start();
    port.controller.add(TaskProgressUpdate(port.enqueued.single, 0.5));
    await Future<void>.delayed(Duration.zero);
    expect(seen, isNotEmpty);
    expect(seen.last[7]?.title, 'Mario');
  });

  test('updates for unknown tasks are ignored', () async {
    await start();
    final other = DownloadTask(url: 'http://x/y', metaData: '{}');
    port.controller.add(TaskStatusUpdate(other, TaskStatus.complete));
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress.keys, [7]);
  });

  test('a running update keeps the game running', () async {
    await start();
    port.controller.add(
      TaskStatusUpdate(port.enqueued.single, TaskStatus.running),
    );
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[7]?.status, GameProgressStatus.running);
  });

  test('retry puts a failed game back to running', () async {
    await start();
    port.controller.add(
      TaskStatusUpdate(port.enqueued.single, TaskStatus.failed),
    );
    await Future<void>.delayed(Duration.zero);
    await manager.retryGame(7);
    expect(manager.progress[7]?.status, GameProgressStatus.running);
  });

  test('a multi-file game completes only after the last file', () async {
    const second = GameFileModel(
      id: 43,
      name: 'd.bin',
      relativePath: 'snes/d.bin',
      role: FileRole.support,
      discNumber: null,
      version: '',
      size: 1024,
    );
    const twoFileGame = GameDetail(
      id: 8,
      title: 'Tekken',
      systemCode: 'snes',
      systemName: 'SNES',
      hasCover: false,
      totalSize: 2048,
      files: [file, second],
    );
    await manager.downloadGame(
      game: twoFileGame,
      selectedIds: {42, 43},
      local: none,
      serverUrl: 'http://nas:8000',
      authHeaders: const {'Authorization': 'Token t'},
      settings: settings,
    );
    port.lengths['/roms/snes/m.sfc'] = 1024;
    port.lengths['/roms/snes/d.bin'] = 1024;
    port.controller.add(
      TaskStatusUpdate(port.enqueued.first, TaskStatus.complete),
    );
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[8]?.status, GameProgressStatus.running);
    port.controller.add(
      TaskStatusUpdate(port.enqueued.last, TaskStatus.complete),
    );
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[8]?.status, GameProgressStatus.complete);
    expect(manager.progress[8]?.progress, 1);
  });

  test('PermissionDeniedException explains itself', () {
    expect(
      PermissionDeniedException().toString(),
      'Brak dostępu do katalogu ROMów',
    );
  });

  test('downloadManagerProvider wires the ports', () {
    final container = ProviderContainer(
      overrides: [
        downloaderPortProvider.overrideWithValue(FakeDownloaderPort()),
        permissionsPortProvider.overrideWithValue(
          FakePermissionsPort(granted: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(downloadManagerProvider), isA<DownloadManager>());
  });

  test('waitingToRetry keeps the game running', () async {
    await start();
    port.controller.add(
      TaskStatusUpdate(port.enqueued.single, TaskStatus.waitingToRetry),
    );
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[7]?.status, GameProgressStatus.running);
  });

  test('the provider-built manager runs a full download', () async {
    final providerPort = FakeDownloaderPort();
    final container = ProviderContainer(
      overrides: [
        downloaderPortProvider.overrideWithValue(providerPort),
        permissionsPortProvider.overrideWithValue(
          FakePermissionsPort(granted: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    final provided = container.read(downloadManagerProvider);
    await provided.downloadGame(
      game: game,
      selectedIds: {42},
      local: none,
      serverUrl: 'http://nas:8000',
      authHeaders: const {'Authorization': 'Token t'},
      settings: settings,
    );
    providerPort.lengths['/roms/snes/m.sfc'] = 1024;
    providerPort.controller.add(
      TaskStatusUpdate(providerPort.enqueued.single, TaskStatus.complete),
    );
    await Future<void>.delayed(Duration.zero);
    expect(provided.progress[7]?.status, GameProgressStatus.complete);
  });
}
