import 'package:flutter/material.dart';

import 'tokens.dart';

export 'tokens.dart';

/// Focus for the Material buttons: the accent ring `FocusGlow` draws around
/// the glass surfaces, so a pad never loses track of where it is.
///
/// [idle] keeps the border a button already had when nothing is focused —
/// without it an `OutlinedButton` would lose its outline entirely.
ButtonStyle focusableButtonStyle({BorderSide? idle}) => ButtonStyle(
  overlayColor: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.focused)
        ? kAccent.withValues(alpha: 0.18)
        : null,
  ),
  side: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.focused)
        ? const BorderSide(color: kAccent, width: 2)
        : idle,
  ),
);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final scheme = base.colorScheme.copyWith(
    primary: kAccent,
    onPrimary: kBgBottom,
    secondary: kAccentAlt,
    surface: kBgMid,
    onSurface: kText,
    error: kDanger,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: kText,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: base.textTheme.apply(bodyColor: kText, displayColor: kText),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kGlass,
      labelStyle: const TextStyle(color: kTextDim),
      hintStyle: const TextStyle(color: kTextDim),
      helperStyle: const TextStyle(color: kTextDim),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kGlassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kGlassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kAccent),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? kAccent : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(kBgBottom),
      side: const BorderSide(color: kTextDim),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? kBgBottom : kTextDim,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? kAccent : kGlass,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kDialogBg,
      contentTextStyle: TextStyle(color: kText),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: kDialogBg),
    popupMenuTheme: PopupMenuThemeData(
      color: kDialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kAccent),
    dividerColor: kGlassBorder,
    elevatedButtonTheme: ElevatedButtonThemeData(style: focusableButtonStyle()),
    textButtonTheme: TextButtonThemeData(style: focusableButtonStyle()),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: focusableButtonStyle(
        idle: const BorderSide(color: kGlassBorder),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: focusableButtonStyle()),
    // `DropdownButton` reads its focus tint straight off the theme.
    focusColor: kGlass,
  );
}

/// Gradient background for the whole app — Scaffolds are transparent.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: child,
      );
}
