import 'package:droplet/app/widgets/circle_icon_button.dart';
import 'package:droplet/app/widgets/glass_panel.dart';
import 'package:droplet/app/widgets/pill.dart';
import 'package:droplet/app/widgets/primary_button.dart';
import 'package:droplet/app/widgets/section_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('GlassPanel renders child and reacts to tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(GlassPanel(onTap: () => taps++, child: const Text('x'))),
    );
    await tester.tap(find.text('x'));
    expect(taps, 1);
  });

  testWidgets('GlassPanel without onTap has no InkWell', (tester) async {
    await tester.pumpWidget(_wrap(const GlassPanel(child: Text('x'))));
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('PrimaryButton: label, ghost, busy, disabled', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(PrimaryButton(label: 'Go', onPressed: () => taps++)),
    );
    await tester.tap(find.text('Go'));
    expect(taps, 1);

    await tester.pumpWidget(
      _wrap(const PrimaryButton(label: 'Go', onPressed: null, ghost: true)),
    );
    await tester.tap(find.text('Go'), warnIfMissed: false);
    expect(taps, 1);

    await tester.pumpWidget(
      _wrap(PrimaryButton(label: 'Go', onPressed: () {}, busy: true)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Go'), findsNothing);
  });

  testWidgets('CircleIconButton taps and exposes tooltip', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        CircleIconButton(
          icon: Icons.arrow_back,
          tooltip: 'Wstecz',
          onPressed: () => taps++,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.arrow_back));
    expect(taps, 1);
    expect(find.byTooltip('Wstecz'), findsOneWidget);
  });

  testWidgets('Pill plain and accent', (tester) async {
    await tester.pumpWidget(
      _wrap(const Row(children: [Pill('SNES'), Pill('OK', accent: true)])),
    );
    expect(find.text('SNES'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('SectionLabel with tappable trailing', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        SectionLabel('Pliki', trailing: 'Wyczyść', onTrailingTap: () => taps++),
      ),
    );
    await tester.tap(find.text('Wyczyść'));
    expect(taps, 1);
    await tester.pumpWidget(_wrap(const SectionLabel('Pliki')));
    expect(find.text('Wyczyść'), findsNothing);
  });
}
