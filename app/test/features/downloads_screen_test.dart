import 'package:background_downloader/background_downloader.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/download_manager.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/features/downloads/downloads_screen.dart';
import 'package:droplet/features/downloads/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_permissions_port.dart';

GoRouter _router() => GoRouter(
      initialLocation: '/downloads',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: 'downloads',
              builder: (_, __) => const DownloadsScreen(),
            ),
            GoRoute(
              path: 'game/:id',
              builder: (_, s) =>
                  Scaffold(body: Text('Gra ${s.pathParameters['id']}')),
            ),
          ],
        ),
      ],
    );

/// A downloads screen fed by the given static list — used for tests that
/// only exercise layout/aggregation, not actions that must reach the
/// manager (those seed a real download instead, see [_screenLive] below).
Widget _screen(List<GameProgress> active, DownloadManager manager) =>
    ProviderScope(
      overrides: [
        activeDownloadsProvider.overrideWith((ref) => active),
        downloadManagerProvider.overrideWithValue(manager),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

/// A downloads screen backed by the real [activeDownloadsProvider], reading
/// straight from [manager] — used whenever a test taps an action and needs
/// the manager (and its fake port) to actually observe it.
Widget _screenLive(DownloadManager manager) => ProviderScope(
      overrides: [downloadManagerProvider.overrideWithValue(manager)],
      child: MaterialApp.router(routerConfig: _router()),
    );

GameProgress at(
  GameProgressStatus status, {
  int id = 7,
  double progress = 0.5,
  int done = 500,
  int total = 1000,
  int? speed,
}) =>
    GameProgress(
      gameId: id,
      title: 'Mario',
      systemCode: 'snes',
      hasCover: false,
      progress: progress,
      status: status,
      bytesDone: done,
      bytesTotal: total,
      speedBytesPerSec: speed,
    );

const _file = GameFileModel(
  id: 42,
  name: 'm.sfc',
  relativePath: 'snes/m.sfc',
  role: FileRole.base,
  discNumber: null,
  version: '',
  size: 1024,
);

GameDetail _game(int id) => GameDetail(
      id: id,
      title: 'Mario',
      systemCode: 'snes',
      systemName: 'SNES',
      hasCover: false,
      totalSize: 1024,
      files: const [_file],
    );

const _localNone = LocalGameState(
  status: InstallStatus.none,
  updateAvailable: false,
  missing: [_file],
  presentPaths: [],
);

final _settings = StorageSettings('/roms', const {});

void main() {
  late FakeDownloaderPort port;
  late DownloadManager manager;

  setUp(() {
    port = FakeDownloaderPort();
    manager = DownloadManager(
      port,
      FakePermissionsPort(granted: true),
      onGameChanged: (_) {},
    );
  });

  tearDown(() => manager.dispose());

  /// Seeds a real, running download for [gameId] on [manager] — mirrors
  /// `test/core/download_manager_test.dart`'s `start()` so action taps have
  /// a real task in the fake port to act on, instead of a no-op override.
  Future<void> startDownload(int gameId) => manager.downloadGame(
        game: _game(gameId),
        selectedIds: {42},
        local: _localNone,
        serverUrl: 'http://nas:8000',
        authHeaders: const {'Authorization': 'Token t'},
        settings: _settings,
      );

  test('progressSubtitle per status', () {
    expect(progressSubtitle(at(GameProgressStatus.running, speed: 2048)),
        '500 B / 1000 B · 2.0 KB/s');
    expect(progressSubtitle(at(GameProgressStatus.running)), '500 B / 1000 B');
    expect(progressSubtitle(at(GameProgressStatus.paused)),
        'Wstrzymane · 500 B / 1000 B');
    expect(progressSubtitle(at(GameProgressStatus.failed)),
        'Błąd pobierania — ponów');
    expect(progressSubtitle(at(GameProgressStatus.complete)), 'Gotowe · 1000 B');
  });

  testWidgets('empty state', (tester) async {
    await tester.pumpWidget(_screen(const [], manager));
    await tester.pumpAndSettle();
    expect(find.text('Brak pobierań'), findsOneWidget);
    expect(find.text('Brak aktywnych'), findsOneWidget);
  });

  testWidgets('header sums what is left; card opens the game', (tester) async {
    await tester.pumpWidget(
      _screen([at(GameProgressStatus.running), at(GameProgressStatus.paused, id: 8)], manager),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 aktywnych · pozostało 1000 B'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    await tester.tap(find.text('Mario').first);
    await tester.pumpAndSettle();
    expect(find.text('Gra 7'), findsOneWidget);
  });

  testWidgets('pause reaches the manager', (tester) async {
    await startDownload(7);
    final taskId = port.enqueued.single.taskId;
    await tester.pumpWidget(_screenLive(manager));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pumpAndSettle();
    expect(port.paused, [taskId]);
  });

  // Note: `port.controller` is a plain (non-`sync`) `StreamController`, so
  // `.add(...)` delivers to its listener via a real, zero-duration `Timer`
  // — not a microtask. Under `AutomatedTestWidgetsFlutterBinding`, real
  // Timers don't fire on their own (nothing advances real wall-clock time),
  // so neither a bare `await Future.delayed(...)` nor `tester.pumpAndSettle()`
  // alone flushes it — both leave `_DownloadCard` showing the stale status
  // until the framework's own timeout. `tester.runAsync(...)` steps outside
  // that zone into real async execution just long enough for the Timer (and
  // the resulting `DownloadManager._onStatus` -> `_emit()` -> Riverpod
  // `StreamProvider` chain) to actually run; `pumpAndSettle()` afterwards
  // rebuilds the widget tree from the now-updated state.
  Future<void> deliver(TaskStatusUpdate update, WidgetTester tester) =>
      tester.runAsync(() async {
        port.controller.add(update);
        await Future<void>.delayed(Duration.zero);
      });

  testWidgets('resume reaches the manager', (tester) async {
    await startDownload(7);
    final task = port.enqueued.single;
    await tester.pumpWidget(_screenLive(manager));
    await tester.pumpAndSettle();
    await deliver(TaskStatusUpdate(task, TaskStatus.paused), tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    expect(port.resumed, [task.taskId]);
  });

  testWidgets('cancel reaches the manager', (tester) async {
    await startDownload(7);
    final taskId = port.enqueued.single.taskId;
    await tester.pumpWidget(_screenLive(manager));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(port.cancelled, [taskId]);
    expect(manager.progress.containsKey(7), isFalse);
  });

  testWidgets('retry reaches the manager', (tester) async {
    await startDownload(7);
    final task = port.enqueued.single;
    await tester.pumpWidget(_screenLive(manager));
    await tester.pumpAndSettle();
    await deliver(TaskStatusUpdate(task, TaskStatus.failed), tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(port.enqueued.length, 2);
  });

  testWidgets('a failed download can be cancelled', (tester) async {
    await startDownload(7);
    final task = port.enqueued.single;
    await tester.pumpWidget(_screenLive(manager));
    await tester.pumpAndSettle();
    await deliver(TaskStatusUpdate(task, TaskStatus.failed), tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(port.cancelled, [task.taskId]);
    expect(manager.progress.containsKey(7), isFalse);
  });

  testWidgets('Wyczyść drops only the complete entry', (tester) async {
    await startDownload(7);
    await startDownload(9);
    final completedTask = port.enqueued[0];
    final failedTask = port.enqueued[1];
    await tester.pumpWidget(_screenLive(manager));
    await tester.pumpAndSettle();

    port.lengths['/roms/snes/m.sfc'] = 1024;
    await tester.runAsync(() async {
      port.controller.add(TaskStatusUpdate(completedTask, TaskStatus.complete));
      port.controller.add(TaskStatusUpdate(failedTask, TaskStatus.failed));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(manager.progress[7]?.status, GameProgressStatus.complete);
    expect(manager.progress[9]?.status, GameProgressStatus.failed);

    expect(find.text('Zakończone'), findsOneWidget);
    await tester.tap(find.text('Wyczyść'));
    await tester.pumpAndSettle();
    expect(manager.progress.containsKey(7), isFalse);
    expect(manager.progress.containsKey(9), isTrue);
  });

  test('activeCountProvider counts running and paused', () {
    final container = ProviderContainer(
      overrides: [
        activeDownloadsProvider.overrideWith(
          (ref) => [
            at(GameProgressStatus.running),
            at(GameProgressStatus.paused, id: 8),
            at(GameProgressStatus.complete, id: 9),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(activeCountProvider), 2);
  });
}
