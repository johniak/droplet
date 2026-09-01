import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows server url and logout', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith(() => _FakeSession())],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('http://nas:8000'), findsOneWidget);
    expect(find.text('Wyloguj'), findsOneWidget);
  });

  testWidgets('logout clears the session', (tester) async {
    final repo = SessionRepository(MemoryKeyValueStore());
    await repo.save(const Session(serverUrl: 'http://nas:8000', token: 't'));
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: SettingsScreen());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wyloguj'));
    await tester.pumpAndSettle();
    expect(await repo.load(), isNull);
    expect(container.read(sessionProvider).value, isNull);
  });

  testWidgets('without a session the server row is empty', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider
              .overrideWithValue(SessionRepository(MemoryKeyValueStore())),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nie zalogowano'), findsOneWidget);
  });
}

class _FakeSession extends SessionController {
  @override
  Future<Session?> build() async =>
      const Session(serverUrl: 'http://nas:8000', token: 't');
}
