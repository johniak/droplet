import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

const server = String.fromEnvironment('E2E_SERVER');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Clean slate on the device: an earlier (possibly aborted) run may have
    // left a session behind.
    await const FlutterSecureStorage().deleteAll();
    // Seed: scan the fixture library through the API so it is not empty.
    final client = ApiClient(baseUrl: server);
    final token = await client.login('e2e', 'e2e-pass-123');
    await ApiClient(baseUrl: server, token: token).triggerScan();
    await Future<void>.delayed(const Duration(seconds: 5));
  });

  testWidgets('login, browse library, open game detail', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DropletApp()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), server);
    await tester.enterText(fields.at(1), 'e2e');
    await tester.enterText(fields.at(2), 'e2e-pass-123');
    await tester.tap(find.text('Zaloguj'));
    await tester.pumpAndSettle(const Duration(seconds: 10));

    await pumpUntil(tester, find.text('Super Mario World'));

    // Nagłówek półki systemu prowadzi do widoku systemu. Ekran główny ma
    // wiele Scrollable (pionowa lista + pozioma lista w każdej półce) —
    // trzeba wskazać zewnętrzną listę, bo domyślny find.byType(Scrollable)
    // jest niejednoznaczny.
    await tester.scrollUntilVisible(
      find.text('Nintendo Switch'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Nintendo Switch'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Hollow Knight'));
    expect(find.text('Super Mario World'), findsNothing);

    await tester.tap(find.text('Hollow Knight').first);
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Aktualizacja'));
    expect(find.text('Aktualizacja'), findsOneWidget);

    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Hollow Knight'));

    await pumpUntil(tester, find.byKey(const Key('nav-settings')));
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wyloguj'));
    await tester.pumpAndSettle();
    expect(find.text('Zaloguj'), findsOneWidget);
  });
}
