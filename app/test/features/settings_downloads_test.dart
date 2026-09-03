import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/launch/emulator_settings.dart';
import 'package:droplet/core/launch/launch_request.dart';
import 'package:droplet/core/platform/launcher_port.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/core/platform/permissions_port.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_launcher_port.dart';
import '../fakes/fake_permissions_port.dart';

Widget _screen({
  required StorageSettingsRepository repo,
  required PermissionsPort port,
  FakeLauncherPort? picker,
}) =>
    ProviderScope(
      overrides: [
        launcherPortProvider.overrideWithValue(picker ?? FakeLauncherPort()),
        sessionRepositoryProvider
            .overrideWithValue(SessionRepository(MemoryKeyValueStore())),
        storageSettingsRepositoryProvider.overrideWithValue(repo),
        permissionsPortProvider.overrideWithValue(port),
        downloaderPortProvider.overrideWithValue(FakeDownloaderPort()),
        librarySnapshotProvider.overrideWith(
          (ref) async => const LibrarySnapshot(
            systems: [],
            games: [],
            manifest: [],
            fromCache: false,
            previousIds: {},
          ),
        ),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('base dir is edited through a dialog', (tester) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await tester.pumpWidget(
      _screen(repo: repo, port: FakePermissionsPort(granted: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text(defaultBaseDir), findsOneWidget);
    expect(find.text('Granted'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('base-dir-field')), '/tmp/roms');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await repo.load()).baseDir, '/tmp/roms');
    expect(find.text('/tmp/roms'), findsOneWidget);
  });

  testWidgets('cancel leaves the dir alone', (tester) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await tester.pumpWidget(
      _screen(repo: repo, port: FakePermissionsPort(granted: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('base-dir-field')), '/nope');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await repo.load()).baseDir, defaultBaseDir);
  });

  testWidgets('grant button requests permission', (tester) async {
    final port = FakePermissionsPort(granted: false, grantOnRequest: true);
    await tester.pumpWidget(
      _screen(repo: StorageSettingsRepository(SharedPreferencesAsync()), port: port),
    );
    await tester.pumpAndSettle();
    // "None" is now said by both the permission row and "Unknown on
    // device", so the finder targets a specific row.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('File access'),
          matching: find.byType(SettingsRow),
        ),
        matching: find.text('None'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('grant-permission')));
    await tester.pumpAndSettle();
    expect(port.requests, 1);
    expect(find.text('Granted'), findsOneWidget);
  });

  testWidgets('wifi-only switch persists', (tester) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await tester.pumpWidget(
      _screen(repo: repo, port: FakePermissionsPort(granted: true)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('wifi-only')), 200);
    await tester.tap(find.byKey(const Key('wifi-only')));
    await tester.pumpAndSettle();
    expect((await repo.load()).wifiOnly, isTrue);
  });

  testWidgets('settings load error is shown', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider
              .overrideWithValue(SessionRepository(MemoryKeyValueStore())),
          storageSettingsProvider
              .overrideWith((ref) async => throw StateError('prefs')),
          permissionsPortProvider
              .overrideWithValue(FakePermissionsPort(granted: true)),
          downloaderPortProvider.overrideWithValue(FakeDownloaderPort()),
          librarySnapshotProvider.overrideWith(
            (ref) async => const LibrarySnapshot(
              systems: [],
              games: [],
              manifest: [],
              fromCache: false,
              previousIds: {},
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
  });

  testWidgets('Browse fills the field, saves the tree, and Save persists it',
      (tester) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    final picker = FakeLauncherPort(
      tree: const RomTree(
        uri: 'content://tree',
        path: '/storage/emulated/0/EMU/ROMs',
      ),
    );
    await tester.pumpWidget(_screen(
      repo: repo,
      port: FakePermissionsPort(granted: true),
      picker: picker,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('browse-folder')));
    await tester.pumpAndSettle();
    expect(picker.picks, 1);
    expect(find.text('/storage/emulated/0/EMU/ROMs'), findsOneWidget);
    // The same grant is the tree the emulators read ROMs through, so the
    // Emulators screen has nothing left to ask for.
    final tree = await EmulatorSettingsRepository(
      SharedPreferencesAsync(),
    ).romTree();
    expect(tree!.uri, 'content://tree');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await repo.load()).baseDir, '/storage/emulated/0/EMU/ROMs');
  });

  testWidgets('a cancelled pick leaves the typed path alone', (tester) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    final picker = FakeLauncherPort();
    await tester.pumpWidget(_screen(
      repo: repo,
      port: FakePermissionsPort(granted: true),
      picker: picker,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('base-dir-field')), '/typed');
    await tester.tap(find.byKey(const Key('browse-folder')));
    await tester.pumpAndSettle();
    expect(picker.picks, 1);
    expect(find.text('/typed'), findsOneWidget);
    expect(
      await EmulatorSettingsRepository(SharedPreferencesAsync()).romTree(),
      isNull,
    );
  });

  testWidgets('a tree we cannot name a path for keeps the typed text', (
    tester,
  ) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    final picker = FakeLauncherPort(tree: const RomTree(uri: 'content://sd'));
    await tester.pumpWidget(_screen(
      repo: repo,
      port: FakePermissionsPort(granted: true),
      picker: picker,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('base-dir-field')), '/typed');
    await tester.tap(find.byKey(const Key('browse-folder')));
    await tester.pumpAndSettle();
    expect(find.text('/typed'), findsOneWidget);
    expect(
      find.text('Pick a folder on internal storage or type the path'),
      findsOneWidget,
    );
    // The grant itself is still worth keeping.
    expect(
      (await EmulatorSettingsRepository(SharedPreferencesAsync()).romTree())!
          .uri,
      'content://sd',
    );
  });
}
