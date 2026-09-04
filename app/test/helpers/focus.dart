import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// True when the `FocusGlow` inside [container] draws its accent ring, i.e.
/// when it holds the focus.
bool hasGlow(WidgetTester tester, Finder container) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: container,
          matching: find.byKey(const Key('focus-glow-ring')),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).border != null;
}
