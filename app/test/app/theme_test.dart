import 'package:droplet/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme is built on the Glass tokens', () {
    final theme = buildTheme();
    expect(theme.colorScheme.primary, kAccent);
    expect(theme.colorScheme.onPrimary, kBgBottom);
    expect(theme.scaffoldBackgroundColor, Colors.transparent);
    expect(theme.inputDecorationTheme.filled, isTrue);
  });

  test('checkbox and switch colors resolve for selected and unselected', () {
    final theme = buildTheme();

    final fillColor = theme.checkboxTheme.fillColor!;
    expect(fillColor.resolve({WidgetState.selected}), kAccent);
    expect(fillColor.resolve({}), Colors.transparent);

    final thumbColor = theme.switchTheme.thumbColor!;
    expect(thumbColor.resolve({WidgetState.selected}), kBgBottom);
    expect(thumbColor.resolve({}), kTextDim);

    final trackColor = theme.switchTheme.trackColor!;
    expect(trackColor.resolve({WidgetState.selected}), kAccent);
    expect(trackColor.resolve({}), kGlass);
  });

  test('buttons get an accent ring and tint while focused', () {
    final theme = buildTheme();
    for (final style in [
      theme.elevatedButtonTheme.style!,
      theme.textButtonTheme.style!,
      theme.iconButtonTheme.style!,
    ]) {
      expect(
        style.overlayColor!.resolve({WidgetState.focused}),
        kAccent.withValues(alpha: 0.18),
      );
      expect(style.overlayColor!.resolve({}), isNull);
      expect(
        style.side!.resolve({WidgetState.focused}),
        const BorderSide(color: kAccent, width: 2),
      );
      expect(style.side!.resolve({}), isNull);
    }
    // An outlined button keeps its outline when nothing is focused.
    final outlined = theme.outlinedButtonTheme.style!;
    expect(
      outlined.side!.resolve({}),
      const BorderSide(color: kGlassBorder),
    );
    expect(theme.focusColor, kGlass);
  });

  testWidgets('AppBackground paints a gradient behind its child', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppBackground(child: Text('x'))),
    );
    expect(find.text('x'), findsOneWidget);
    final box = tester.widget<DecoratedBox>(
      find.ancestor(of: find.text('x'), matching: find.byType(DecoratedBox)).first,
    );
    expect((box.decoration as BoxDecoration).gradient, kBgGradient);
  });
}
