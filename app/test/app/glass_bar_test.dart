import 'package:droplet/app/widgets/glass_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _focused(WidgetTester tester, String key) =>
    (tester.widget<DecoratedBox>(
              find.descendant(
                of: find.byKey(Key(key)),
                matching: find.byKey(const Key('focus-glow-ring')),
              ),
            ).decoration
            as BoxDecoration)
        .border !=
    null;

void main() {
  testWidgets('three tabs, taps report index, badge shows count', (
    tester,
  ) async {
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GlassBar(
            currentIndex: 0,
            onTap: taps.add,
            badge: 2,
          ),
        ),
      ),
    );
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-downloads')));
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.tap(find.byKey(const Key('nav-library')));
    expect(taps, [1, 2, 0]);
  });

  testWidgets('no badge when nothing downloads', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GlassBar(currentIndex: 1, onTap: (_) {}),
        ),
      ),
    );
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('the pad walks the tabs and picks one with A', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GlassBar(currentIndex: 0, onTap: taps.add),
        ),
      ),
    );
    FocusScope.of(tester.element(find.byType(GlassBar))).nextFocus();
    await tester.pumpAndSettle();
    expect(_focused(tester, 'nav-library'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_focused(tester, 'nav-library'), isFalse);
    expect(_focused(tester, 'nav-downloads'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(taps, [1]);
  });
}
