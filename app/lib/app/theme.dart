import 'package:flutter/material.dart';

const kBg = Color(0xFF0E1116);
const kSurface = Color(0xFF161B22);
const kAccent = Color(0xFF3FB6F0);
const kText = Color(0xFFE6EDF3);
const kTextDim = Color(0xFF8B949E);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: base.colorScheme.copyWith(
      primary: kAccent,
      surface: kSurface,
      onSurface: kText,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kText,
      elevation: 0,
    ),
  );
}
