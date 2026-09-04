import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle(const Duration(seconds: 10));

    await pumpUntil(tester, find.text('Super Mario World'));

    // The pad alone: the first card of the first shelf holds the focus, so A
    // opens a game without touching the screen. The detail screen hides the
    // nav bar, which is how we know we got there.
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.byKey(const Key('back-button')));
    expect(find.byKey(const Key('nav-settings')), findsNothing);
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Super Mario World'));

    // The system shelf header leads to the system view. The home screen has
    // many Scrollables (a vertical list + a horizontal list in each shelf) —
    // the outer list needs to be targeted explicitly, because the default
    // find.byType(Scrollable) is ambiguous.
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
    await pumpUntil(tester, find.text('Update'));
    expect(find.text('Update'), findsOneWidget);

    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Hollow Knight'));

    // R1 walks the tabs: Library → Downloads → Settings.
    await pumpUntil(tester, find.byKey(const Key('nav-settings')));
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Nothing active'));
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Sign out'));

    // Emulators: the test device has none installed, so every system row
    // says which ones it would take.
    await tester.scrollUntilVisible(find.text('Emulator per system'), 200);
    await tester.tap(find.text('Emulator per system'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Folder access for emulators'));
    expect(find.textContaining('Not installed: Eden'), findsOneWidget);
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Sign out'), -200);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    // The row only asks; the dialog's own Sign out button does it.
    expect(find.text('Sign out?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Sign out'),
      ),
    );
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Sign in'));
    expect(find.text('Sign in'), findsOneWidget);
  });
}
