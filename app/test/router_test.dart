import 'package:droplet/app/router.dart';
import 'package:droplet/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every route renders its screen', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router, theme: buildTheme()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Droplet'), findsOneWidget);

    router.go('/');
    await tester.pumpAndSettle();
    expect(find.text('Biblioteka'), findsOneWidget);

    router.go('/game/7');
    await tester.pumpAndSettle();
    expect(find.text('Gra 7'), findsOneWidget);

    router.go('/settings');
    await tester.pumpAndSettle();
    expect(find.text('Ustawienia'), findsOneWidget);
  });
}
