import 'package:droplet/app/widgets/glass_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/focus.dart';

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
  // The focus glow follows Flutter's highlight mode: visible only after a key
  // or pad event. These tests assert on the glow, so they run in that mode.
  setUp(() => FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional);
  tearDown(() => FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.automatic);

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

  testWidgets('the tabs stay tappable but out of the pad\'s way', (
    tester,
  ) async {
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GlassBar(currentIndex: 0, onTap: taps.add),
        ),
      ),
    );
    // Directional focus cannot cross a page's route scope into the bar, so a
    // tab the pad could reach only by accident is worse than none: L1/R1
    // switch tabs instead (spec §4).
    FocusScope.of(tester.element(find.byType(GlassBar))).nextFocus();
    await tester.pumpAndSettle();
    expect(focusedAncestor<GlassBar>(), isNull);
    expect(_focused(tester, 'nav-library'), isFalse);

    await tester.tap(find.byKey(const Key('nav-downloads')));
    expect(taps, [1]);
  });
}
