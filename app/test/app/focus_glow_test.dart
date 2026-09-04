import 'package:droplet/app/theme.dart';
import 'package:droplet/app/widgets/focus_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

BoxDecoration _ring(WidgetTester tester, Finder inside) =>
    tester
            .widget<DecoratedBox>(
              find.descendant(
                of: inside,
                matching: find.byKey(const Key('focus-glow-ring')),
              ),
            )
            .decoration
        as BoxDecoration;

Widget _wrap(Widget child) => MaterialApp(
  theme: buildTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  // The glow follows Flutter's focus highlight mode; tests that assert on it
  // force the "key/pad" mode, and one test below checks the touch behaviour.
  setUp(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional,
  );
  tearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );

  _ringTests();

  testWidgets('no glow in touch mode until a key is pressed', (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(FocusGlow(focusNode: node, onTap: () {}, child: const Text('Go'))),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    expect(_ring(tester, find.byType(FocusGlow)).border, isNull);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_ring(tester, find.byType(FocusGlow)).border, isNotNull);
  });

  testWidgets('a tap calls onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(FocusGlow(onTap: () => taps++, child: const Text('Go'))),
    );
    await tester.tap(find.text('Go'));
    expect(taps, 1);
  });

  testWidgets('focus draws the ring, gameButtonA activates', (tester) async {
    var taps = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(
        FocusGlow(
          focusNode: node,
          onTap: () => taps++,
          child: const Text('Go'),
        ),
      ),
    );
    final glow = find.byType(FocusGlow);
    expect(_ring(tester, glow).border, isNull);

    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    expect(_ring(tester, glow).border, isNotNull);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      1.04,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('autofocus takes the focus on the first frame', (tester) async {
    await tester.pumpWidget(
      _wrap(FocusGlow(autofocus: true, onTap: () {}, child: const Text('Go'))),
    );
    await tester.pumpAndSettle();
    expect(_ring(tester, find.byType(FocusGlow)).border, isNotNull);
  });

  testWidgets('focus scrolls the item into view', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          height: 400,
          width: 300,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < 20; i++)
                  SizedBox(
                    height: 100,
                    child: FocusGlow(
                      focusNode: i == 19 ? node : null,
                      onTap: () {},
                      child: Text('item $i'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final last = find.text('item 19');
    expect(tester.getRect(last).top, greaterThan(600));

    node.requestFocus();
    await tester.pumpAndSettle();
    final rect = tester.getRect(last);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(600));
  });

  testWidgets('focus outside a Scrollable is harmless', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(FocusGlow(focusNode: node, onTap: () {}, child: const Text('Go'))),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a surface with no action keeps the focus but ignores taps', (
    tester,
  ) async {
    // What a busy PrimaryButton looks like: still the selected thing on
    // screen, just inert until the launch finishes.
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(FocusGlow(focusNode: node, onTap: null, child: const Text('Go'))),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    expect(_ring(tester, find.byType(FocusGlow)).border, isNotNull);
    await tester.tap(find.text('Go'), warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled takes no focus and ignores taps', (tester) async {
    var taps = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(
        FocusGlow(
          enabled: false,
          focusNode: node,
          scale: 1,
          onTap: () => taps++,
          child: const Text('Go'),
        ),
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isFalse);
    expect(_ring(tester, find.byType(FocusGlow)).border, isNull);
    await tester.tap(find.text('Go'), warnIfMissed: false);
    expect(taps, 0);
  });
}

void _ringTests() {
  BoxDecoration halo(WidgetTester tester, Finder inside) =>
      tester
              .widget<DecoratedBox>(
                find.descendant(
                  of: inside,
                  matching: find.byKey(const Key('focus-glow-halo')),
                ),
              )
              .decoration
          as BoxDecoration;

  testWidgets('a flat surface lights up with a halo and a wash underneath', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(FocusGlow(focusNode: node, onTap: () {}, child: const Text('Row'))),
    );
    final glow = find.byType(FocusGlow);
    expect(halo(tester, glow).color, isNull);
    expect(halo(tester, glow).boxShadow, isNull);
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(halo(tester, glow).color, isNotNull);
    expect(halo(tester, glow).boxShadow, hasLength(2));
    expect(_ring(tester, glow).border, isNotNull);
    expect(_ring(tester, glow).boxShadow, isNull);
  });

  testWidgets('fill: false keeps the halo but skips the wash', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(
        FocusGlow(
          focusNode: node,
          fill: false,
          onTap: () {},
          child: const Text('Go'),
        ),
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    final glow = find.byType(FocusGlow);
    expect(halo(tester, glow).color, isNull);
    expect(halo(tester, glow).boxShadow, hasLength(2));
  });

  testWidgets('ring: false hands the ring to a FocusRing inside', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(
        FocusGlow(
          focusNode: node,
          ring: false,
          onTap: () {},
          child: const Column(
            children: [
              FocusRing(child: Text('Cover')),
              Text('Caption'),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('focus-glow-ring')), findsOneWidget);
    final cover = find.byType(FocusRing);
    expect(_ring(tester, cover).border, isNull);
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(_ring(tester, cover).border, isNotNull);
    expect(halo(tester, cover).boxShadow, hasLength(2));
    expect(halo(tester, cover).color, isNull);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      1.04,
    );
  });

  testWidgets('a FocusRing with no FocusGlow above stays dark', (tester) async {
    await tester.pumpWidget(_wrap(const FocusRing(child: Text('Alone'))));
    expect(_ring(tester, find.byType(FocusRing)).border, isNull);
    expect(FocusGlow.highlighted(tester.element(find.text('Alone'))), isFalse);
  });
}
