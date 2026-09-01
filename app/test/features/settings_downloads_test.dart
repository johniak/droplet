import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
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

import '../fakes/fake_permissions_port.dart';

Widget _screen({
  required StorageSettingsRepository repo,
  required PermissionsPort port,
  List<SystemModel> systems = const [],
}) =>
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => _FakeSession()),
        storageSettingsRepositoryProvider.overrideWithValue(repo),
        permissionsPortProvider.overrideWithValue(port),
        systemsProvider.overrideWith((ref) async => systems),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('download section edits base dir and shows permission', (
    tester,
  ) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await tester.pumpWidget(
      _screen(repo: repo, port: FakePermissionsPort(granted: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pobieranie'), findsOneWidget);
    expect(find.text('Przyznane'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('base-dir-field')),
      '/tmp/roms',
    );
    await tester.pumpAndSettle();
    expect((await repo.load()).baseDir, '/tmp/roms');
  });

  testWidgets('grant button requests permission', (tester) async {
    final port = FakePermissionsPort(granted: false, grantOnRequest: true);
    await tester.pumpWidget(
      _screen(repo: StorageSettingsRepository(SharedPreferencesAsync()), port: port),
    );
    await tester.pumpAndSettle();
    expect(find.text('Brak'), findsOneWidget);
    await tester.tap(find.byKey(const Key('grant-permission')));
    await tester.pumpAndSettle();
    expect(port.requests, 1);
    expect(find.text('Przyznane'), findsOneWidget);
  });

  testWidgets('per-system directories are editable', (tester) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await tester.pumpWidget(
      _screen(
        repo: repo,
        port: FakePermissionsPort(granted: true),
        systems: const [
          SystemModel(id: 1, code: 'psx', name: 'PlayStation', gameCount: 3),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('system-dir-psx')),
      'PlayStation',
    );
    await tester.pumpAndSettle();
    expect((await repo.load()).systemDirs, {'psx': 'PlayStation'});
  });
}

class _FakeSession extends SessionController {
  @override
  Future<Session?> build() async =>
      const Session(serverUrl: 'http://nas:8000', token: 't');
}
