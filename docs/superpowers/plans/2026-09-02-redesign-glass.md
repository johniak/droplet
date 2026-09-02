# Redesign aplikacji „Glass" — plan implementacji

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wymienić warstwę widoków aplikacji Flutter na projekt „Glass" (półki per system, dolna nawigacja z trzema gałęziami, karta gry z rozmytym tłem i widocznym wstecz), zachowując logikę `core/*`, bramkę 100% pokrycia i oba testy e2e.

**Architecture:** Nowe tokeny i wspólne widgety w `app/lib/app/`, powłoka nawigacyjna `StatefulShellRoute.indexedStack` z paskiem `GlassBar`, ekrany w `features/{home,system,game,downloads,settings,auth}`. Dane biblioteki dalej płyną z `librarySnapshotProvider`; dochodzą czyste funkcje `buildShelves`, `applyFilter`, `sortGames` i providery `homeShelvesProvider`, `systemGamesProvider`, `updatableIdsProvider`. `DownloadManager` zyskuje bajty, prędkość i `clearFinished()`; ustawienia zyskują `wifiOnly`.

**Tech Stack:** Flutter 3.32 / Dart 3.8, flutter_riverpod 3.3, go_router 17, cached_network_image, background_downloader 9.5, shared_preferences (Async), flutter_test, integration_test.

**Spec:** `docs/superpowers/specs/2026-09-02-redesign-glass-design.md`

## Global Constraints

- Bramka pokrycia: `./scripts/check_coverage_app.sh` musi kończyć się `100.00%`. Jedyne dozwolone `// coverage:ignore-file` to `lib/core/platform/*_port.dart`; `main()` w `main.dart` zostaje w `coverage:ignore-start/end`. Każda nowa gałąź UI dostaje test — bez wyjątków.
- Biegi częściowe: `cd app && flutter test test/<plik>_test.dart` w trakcie TDD; pełna bramka na koniec każdego taska.
- `flutter analyze` bez ostrzeżeń po każdym tasku.
- Bez nowych zależności w `pubspec.yaml`.
- Bez `BackdropFilter` w przewijanych listach — tylko `GlassBar` i tło hero.
- Wszystkie napisy po polsku, dokładnie jak w specu (testy e2e szukają tekstów: `Zaloguj`, `Nintendo Switch`, `Hollow Knight`, `Aktualizacja`, `Wyloguj`, `Zmień`, `Zapisz`, `Pobierz`, `Zainstalowana`, `Usuń z urządzenia`, `Usuń`).
- Klucze testowe: `nav-library`, `nav-downloads`, `nav-settings`, `back-button`, `base-dir-field`, `grant-permission`, `wifi-only`, `system-dir-{code}`.
- Nazwy plików mierzone przez `cached_network_image` w testach: karty z `hasCover: false` nie tworzą klienta API ani HTTP — utrzymać tę zasadę w nowych widgetach.
- Async `dart:io` nie kończy się w `testWidgets` (patrz RALPH-STATUS) — nie dodawać nowego async IO w widgetach.
- Commity po każdym tasku, prefiksy `feat:` / `refactor:` / `test:` / `docs:`.

---

## Mapa plików

| Plik | Odpowiedzialność |
|---|---|
| `app/lib/app/tokens.dart` (nowy) | kolory, promienie, gradienty, stałe rozmiarów |
| `app/lib/app/theme.dart` | `buildTheme()` na tokenach, `AppBackground` |
| `app/lib/app/widgets/glass_panel.dart`, `primary_button.dart`, `circle_icon_button.dart`, `pill.dart`, `section_label.dart`, `glass_bar.dart` (nowe) | wspólne widgety |
| `app/lib/app/widgets/pulse_box.dart` | skeleton, tylko kolor |
| `app/lib/app/shell.dart` (nowy) | `AppShell` — powłoka z tłem, paskiem statusu i `GlassBar` |
| `app/lib/app/router.dart` | `StatefulShellRoute` |
| `app/lib/core/downloads/storage_settings.dart` | `wifiOnly` |
| `app/lib/core/downloads/task_builder.dart` | `requiresWiFi` |
| `app/lib/core/downloads/download_manager.dart` | bajty, prędkość, `clearFinished` |
| `app/lib/features/library/providers.dart` | snapshot, półki, filtry, sortowanie |
| `app/lib/features/library/widgets/cover_image.dart` | okładka + placeholder |
| `app/lib/features/library/widgets/install_badge.dart` (nowy) | odznaka stanu + zasilanie `installedIds`/`updatableIds` |
| `app/lib/features/library/widgets/game_tile.dart` (nowy) | kafel gridu |
| `app/lib/features/library/widgets/shelf.dart` (nowy) | półka pozioma |
| `app/lib/features/library/widgets/games_grid.dart` (nowy) | grid 2 kolumny |
| `app/lib/features/library/widgets/sort_menu.dart` (nowy) | menu sortowania |
| `app/lib/features/library/widgets/search_field.dart` (nowy) | szukajka |
| `app/lib/features/home/home_screen.dart` (nowy) | ekran główny |
| `app/lib/features/system/system_screen.dart` (nowy) | widok systemu |
| `app/lib/features/game/game_detail_screen.dart`, `providers.dart` | karta gry, `freeBytesProvider` |
| `app/lib/features/downloads/providers.dart` (nowy), `downloads_screen.dart` | pobierania |
| `app/lib/features/settings/settings_screen.dart`, `folders_screen.dart` (nowy) | ustawienia |
| `app/lib/features/auth/login_screen.dart` | logowanie |
| usuwane w Task 12 | `features/library/library_screen.dart`, `widgets/game_card.dart`, ich testy |

---

### Task 1: Tokeny, motyw i tło

**Files:**
- Create: `app/lib/app/tokens.dart`
- Modify: `app/lib/app/theme.dart`
- Modify: `app/lib/app/widgets/pulse_box.dart`
- Test: `app/test/app/theme_test.dart`

**Interfaces:**
- Produces: stałe `kBgTop, kBgMid, kBgBottom, kAccent, kAccentAlt, kText, kTextDim, kDanger, kOk, kGlass, kGlassBorder, kRadiusCard, kRadiusCover, kRadiusBar, kNavHeight, kListBottomPad, kPrimaryGradient, kBgGradient`; `ThemeData buildTheme()`; `class AppBackground extends StatelessWidget { const AppBackground({required Widget child}) }`. Tymczasowe aliasy `kBg`, `kSurface` (usuwane w Task 12) — stare ekrany kompilują się do końca.

- [ ] **Step 1: Test motywu**

```dart
// app/test/app/theme_test.dart
import 'package:droplet/app/theme.dart';
import 'package:droplet/app/tokens.dart';
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
```

- [ ] **Step 2: Uruchom — ma nie kompilować się (brak `tokens.dart`, `AppBackground`)**

Run: `cd app && flutter test test/app/theme_test.dart`

- [ ] **Step 3: Tokeny**

```dart
// app/lib/app/tokens.dart
import 'package:flutter/material.dart';

const kBgTop = Color(0xFF1E2A55);
const kBgMid = Color(0xFF0D1020);
const kBgBottom = Color(0xFF090B14);
const kAccent = Color(0xFF7C9DFF);
const kAccentAlt = Color(0xFF9B6BFF);
const kText = Color(0xFFEEF1FF);
const kTextDim = Color(0xFF8E96B8);
const kDanger = Color(0xFFFF8A8A);
const kOk = Color(0xFF5BE0A0);
const kGlass = Color(0x12FFFFFF); // biały α .07
const kGlassBorder = Color(0x1AFFFFFF); // biały α .10
const kDialogBg = Color(0xFF161B33);

const kRadiusCard = 14.0;
const kRadiusCover = 12.0;
const kRadiusBar = 26.0;
const kNavHeight = 64.0;

/// Dolny padding list pod pływającym paskiem nawigacji.
const kListBottomPad = 104.0;

const kPrimaryGradient = LinearGradient(colors: [kAccent, kAccentAlt]);

const kBgGradient = RadialGradient(
  center: Alignment(-0.8, -1.0),
  radius: 1.6,
  colors: [kBgTop, kBgMid, kBgBottom],
  stops: [0.0, 0.45, 1.0],
);
```

- [ ] **Step 4: Motyw i tło**

```dart
// app/lib/app/theme.dart
import 'package:flutter/material.dart';

import 'tokens.dart';

export 'tokens.dart';

// Aliasy dla ekranów sprzed redesignu — usuwane w Task 12.
const kBg = kBgBottom;
const kSurface = Color(0xFF151A2E);

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
  );
}

/// Gradientowe tło całej aplikacji — Scaffoldy są przezroczyste.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: child,
      );
}
```

- [ ] **Step 5: PulseBox na `kGlass`**

W `app/lib/app/widgets/pulse_box.dart` zamień `color: kSurface` na `color: kGlass` (import `../theme.dart` zostaje, bo eksportuje tokeny).

- [ ] **Step 6: Testy**

Run: `cd app && flutter test test/app/theme_test.dart test/app/pulse_box_test.dart && flutter analyze`
Expected: PASS, brak ostrzeżeń.

- [ ] **Step 7: Commit**

```bash
git add app/lib/app app/test/app/theme_test.dart
git commit -m "feat(app): tokeny Glass, motyw i gradientowe tło"
```

---

### Task 2: Wspólne widgety

**Files:**
- Create: `app/lib/app/widgets/glass_panel.dart`, `primary_button.dart`, `circle_icon_button.dart`, `pill.dart`, `section_label.dart`
- Test: `app/test/app/widgets_test.dart`

**Interfaces:**
- Produces:
  - `GlassPanel({Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(14), double radius = kRadiusCard, VoidCallback? onTap, EdgeInsetsGeometry? margin})`
  - `PrimaryButton({required String label, required VoidCallback? onPressed, bool ghost = false, bool busy = false, Key? key})`
  - `CircleIconButton({required IconData icon, required VoidCallback? onPressed, String? tooltip, Key? key})`
  - `Pill(String text, {bool accent = false})`
  - `SectionLabel(String text, {String? trailing, VoidCallback? onTrailingTap})`

- [ ] **Step 1: Testy widgetów**

```dart
// app/test/app/widgets_test.dart
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
```

- [ ] **Step 2: Uruchom — nie kompiluje się**

Run: `cd app && flutter test test/app/widgets_test.dart`

- [ ] **Step 3: Implementacja**

```dart
// app/lib/app/widgets/glass_panel.dart
import 'package:flutter/material.dart';

import '../tokens.dart';

/// Półprzezroczysta karta bez rozmycia — bezpieczna w listach.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = kRadiusCard,
    this.onTap,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final body = Padding(padding: padding, child: child);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: kGlass,
        borderRadius: shape,
        border: Border.all(color: kGlassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          : Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, borderRadius: shape, child: body),
            ),
    );
  }
}
```

```dart
// app/lib/app/widgets/primary_button.dart
import 'package:flutter/material.dart';

import '../tokens.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.ghost = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool ghost;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final radius = BorderRadius.circular(kRadiusCard);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: ghost ? null : kPrimaryGradient,
          color: ghost ? kGlass : null,
          border: ghost ? Border.all(color: kGlassBorder) : null,
          borderRadius: radius,
          boxShadow: ghost || !enabled
              ? null
              : [
                  BoxShadow(
                    color: kAccent.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: radius,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kText,
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        color: ghost ? kText : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
```

```dart
// app/lib/app/widgets/circle_icon_button.dart
import 'package:flutter/material.dart';

import '../tokens.dart';

/// Okrągły przycisk na ciemnej pastylce — czytelny także na jasnej okładce.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(side: BorderSide(color: kGlassBorder)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: kText),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
```

```dart
// app/lib/app/widgets/pill.dart
import 'package:flutter/material.dart';

import '../tokens.dart';

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent ? kAccent.withValues(alpha: 0.22) : kGlass,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: accent ? kAccent.withValues(alpha: 0.5) : kGlassBorder,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: accent ? const Color(0xFFBFD0FF) : kText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
```

```dart
// app/lib/app/widgets/section_label.dart
import 'package:flutter/material.dart';

import '../tokens.dart';

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.onTrailingTap});

  final String text;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  static const _style = TextStyle(
    color: kTextDim,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
  );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Row(
          children: [
            Expanded(child: Text(text.toUpperCase(), style: _style)),
            if (trailing != null)
              GestureDetector(
                onTap: onTrailingTap,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  trailing!,
                  style: _style.copyWith(
                    color: onTrailingTap == null ? kTextDim : kAccent,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
          ],
        ),
      );
}
```

Uwaga: `SectionLabel` renderuje `text.toUpperCase()`, ale testy szukają po tekście renderowanym — test w Step 1 szuka `Wyczyść` (trailing, bez zmiany wielkości). Sekcje plików na karcie gry (`Aktualizacja`) e2e szuka `find.text('Aktualizacja')` — dlatego **nie** używaj `toUpperCase()` na tekście; użyj zwykłego tekstu, a rozstrzelenie i kolor robią robotę. Popraw: `Text(text, style: _style)`.

- [ ] **Step 4: Testy i analiza**

Run: `cd app && flutter test test/app/widgets_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/app/widgets app/test/app/widgets_test.dart
git commit -m "feat(app): wspólne widgety Glass (panel, przyciski, pigułka, etykieta)"
```

---

### Task 3: Rdzeń — Wi‑Fi, bajty i prędkość pobierania, czyszczenie zakończonych

**Files:**
- Modify: `app/lib/core/downloads/storage_settings.dart`
- Modify: `app/lib/core/downloads/task_builder.dart`
- Modify: `app/lib/core/downloads/download_manager.dart`
- Test: `app/test/core/storage_settings_test.dart`, `app/test/core/task_builder_test.dart`, `app/test/core/download_manager_test.dart`

**Interfaces:**
- Produces:
  - `StorageSettings(baseDir, systemDirs, {bool wifiOnly = false})`; `StorageSettingsRepository.saveWifiOnly(bool)`.
  - `GameProgress` + `systemCode: String`, `hasCover: bool`, `bytesDone: int`, `bytesTotal: int`, `speedBytesPerSec: int?`; `copyWith` przyjmuje też `bytesDone`, `speedBytesPerSec`.
  - `DownloadManager.clearFinished()` — usuwa wpisy `complete` i emituje.

- [ ] **Step 1: Testy ustawień i taska**

Dopisz do `app/test/core/storage_settings_test.dart` (istniejący `setUp` z `InMemorySharedPreferencesAsync.empty()` zostaje):

```dart
  test('wifiOnly defaults to false and persists', () async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    expect((await repo.load()).wifiOnly, isFalse);
    await repo.saveWifiOnly(true);
    expect((await repo.load()).wifiOnly, isTrue);
  });
```

Dopisz do `app/test/core/task_builder_test.dart` (użyj tych samych argumentów co w istniejącym teście `buildTask`, zmień tylko settings):

```dart
  test('wifiOnly setting makes the task require Wi-Fi', () {
    final task = buildTask(
      serverUrl: 'http://nas:8000',
      authHeaders: const {'Authorization': 'Token t'},
      gameId: 7,
      file: file,
      settings: StorageSettings('/roms', const {}, wifiOnly: true),
      systemCode: 'snes',
    );
    expect(task.requiresWiFi, isTrue);
  });
```

(`file` to stała `GameFileModel` już zdefiniowana w tym pliku testowym; jeśli nazywa się inaczej, użyj istniejącej.)

- [ ] **Step 2: Testy managera**

Dopisz do `app/test/core/download_manager_test.dart`. Plik ma już helpery tworzące `DownloadManager` na `FakeDownloaderPort` i `GameDetail` z plikami; użyj ich nazw. Poniżej zakładam `manager`, `port`, `game` (dwa pliki: 1000 B i 3000 B) oraz `Future<void> start()` uruchamiający `downloadGame` z domyślnym wyborem — dopasuj do istniejących helperów.

```dart
  test('progress carries bytes, speed, system and cover', () async {
    await start();
    final tasks = port.enqueued;
    port.controller.add(TaskProgressUpdate(tasks[0], 0.5, 1000, 2.0));
    await Future<void>.delayed(Duration.zero);
    final p = manager.progress[game.id]!;
    expect(p.systemCode, game.systemCode);
    expect(p.hasCover, game.hasCover);
    expect(p.bytesTotal, 4000);
    expect(p.bytesDone, 500);
    expect(p.speedBytesPerSec, 2 * 1024 * 1024);
  });

  test('unknown network speed is null', () async {
    await start();
    port.controller.add(TaskProgressUpdate(port.enqueued[0], 0.1));
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[game.id]!.speedBytesPerSec, isNull);
  });

  test('clearFinished drops complete entries only', () async {
    await start();
    for (final t in port.enqueued) {
      port.lengths['/${t.directory}/${t.filename}'] = expectedSizeOf(t);
      port.controller.add(TaskStatusUpdate(t, TaskStatus.complete));
      await Future<void>.delayed(Duration.zero);
    }
    expect(manager.progress[game.id]!.status, GameProgressStatus.complete);
    manager.clearFinished();
    expect(manager.progress, isEmpty);
  });
```

- [ ] **Step 3: Uruchom — FAIL**

Run: `cd app && flutter test test/core/storage_settings_test.dart test/core/task_builder_test.dart test/core/download_manager_test.dart`

- [ ] **Step 4: Ustawienia i task**

`storage_settings.dart`:

```dart
const _kWifiOnly = 'storage.wifi_only';

class StorageSettings {
  StorageSettings(this.baseDir, this.systemDirs, {this.wifiOnly = false});

  final String baseDir;
  final Map<String, String> systemDirs;

  /// Kolejkuj pobierania tylko na Wi‑Fi (flaga `requiresWiFi` taska).
  final bool wifiOnly;
  // dirFor / pathFor bez zmian
}

// w load():
    final wifiOnly = await _prefs.getBool(_kWifiOnly) ?? false;
    return StorageSettings(baseDir, dirs, wifiOnly: wifiOnly);

// w repozytorium:
  Future<void> saveWifiOnly(bool value) => _prefs.setBool(_kWifiOnly, value);
```

`task_builder.dart` — w `DownloadTask(...)` dodaj `requiresWiFi: settings.wifiOnly,`.

- [ ] **Step 5: GameProgress i manager**

```dart
class GameProgress {
  const GameProgress({
    required this.gameId,
    required this.title,
    required this.systemCode,
    required this.hasCover,
    required this.progress,
    required this.status,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.speedBytesPerSec,
  });

  final int gameId;
  final String title;
  final String systemCode;
  final bool hasCover;
  final double progress;
  final GameProgressStatus status;
  final int bytesDone;
  final int bytesTotal;

  /// null, gdy plugin nie zna prędkości (networkSpeed == -1).
  final int? speedBytesPerSec;

  int get bytesLeft => bytesTotal - bytesDone;

  GameProgress copyWith({
    double? progress,
    GameProgressStatus? status,
    int? bytesDone,
    int? speedBytesPerSec,
  }) =>
      GameProgress(
        gameId: gameId,
        title: title,
        systemCode: systemCode,
        hasCover: hasCover,
        progress: progress ?? this.progress,
        status: status ?? this.status,
        bytesDone: bytesDone ?? this.bytesDone,
        bytesTotal: bytesTotal,
        speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      );
}
```

W `downloadGame` (miejsce, gdzie tworzony jest wpis postępu):

```dart
    _progress[game.id] = GameProgress(
      gameId: game.id,
      title: game.title,
      systemCode: game.systemCode,
      hasCover: game.hasCover,
      progress: 0,
      status: GameProgressStatus.running,
      bytesTotal: needed,
    );
```

W `_onUpdate` przekaż prędkość:

```dart
    if (update is TaskProgressUpdate) {
      _taskProgress[update.task.taskId] = update.progress;
      _recomputeProgress(
        gameId,
        speed: update.networkSpeed > 0
            ? (update.networkSpeed * 1024 * 1024).round()
            : null,
      );
    }
```

`_recomputeProgress`:

```dart
  void _recomputeProgress(int gameId, {int? speed}) {
    final tasks = _tasksByGame[gameId] ?? const <DownloadTask>[];
    var total = 0;
    var done = 0.0;
    for (final task in tasks) {
      final size = expectedSizeOf(task);
      total += size;
      done += size * (_taskProgress[task.taskId] ?? 0);
    }
    final current = _progress[gameId];
    if (current == null || total == 0) return;
    _progress[gameId] = current.copyWith(
      progress: done / total,
      bytesDone: done.round(),
      speedBytesPerSec: speed,
    );
    _emit();
  }
```

W `_onComplete`, gałąź `allDone`: dodaj `bytesDone: allDone ? current.bytesTotal : current.bytesDone`. Nowa metoda:

```dart
  /// Usuwa wpisy zakończone sukcesem; błędy zostają do ponowienia/anulowania.
  void clearFinished() {
    _progress.removeWhere((_, p) => p.status == GameProgressStatus.complete);
    _emit();
  }
```

Popraw istniejące konstrukcje `GameProgress(...)` w testach (`downloads_screen_test.dart`, `download_flow_test.dart`) — dodaj `systemCode: 'snes', hasCover: false`. Te testy i tak są przepisywane w Task 9, ale muszą kompilować się teraz.

- [ ] **Step 6: Testy**

Run: `cd app && flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/lib/core app/test
git commit -m "feat(core): wifiOnly, bajty i prędkość w GameProgress, clearFinished"
```

---

### Task 4: Providery biblioteki — półki, filtry, sortowanie

**Files:**
- Modify: `app/lib/features/library/providers.dart`
- Modify: `app/test/core/sorting_test.dart`
- Test: `app/test/features/shelves_test.dart`

**Interfaces:**
- Consumes: `LibrarySnapshot`, `librarySnapshotProvider`, `LibrarySort`, `sortProvider`, `searchQueryProvider` (istniejące, bez zmian).
- Produces:
  - `class IdSet extends Notifier<Set<int>> { void mark(int id, {required bool installed}) }`; `installedIdsProvider`, `updatableIdsProvider` (oba `NotifierProvider<IdSet, Set<int>>`).
  - `enum SystemFilter { all, installed, updatable }`; `systemFilterProvider` (`NotifierProvider<SystemFilterState, SystemFilter>` z `select(SystemFilter)`).
  - `List<GameSummary> sortGames(List<GameSummary>, LibrarySort)`; `List<GameSummary> applyFilter(List<GameSummary>, SystemFilter, Set<int> installed, Set<int> updatable)`.
  - `class SystemShelf { SystemModel system; List<GameSummary> games; }`; `class HomeShelves { List<GameSummary> recent; List<GameSummary> installed; List<SystemShelf> systems; }`; `HomeShelves buildShelves(List<GameSummary>, List<SystemModel>, Set<int> installedIds, LibrarySort)`; `homeShelvesProvider` (`FutureProvider<HomeShelves>`).
  - `systemGamesProvider` (`FutureProvider.family<List<GameSummary>, String>`) — gry systemu po filtrze i sortowaniu.
  - `gamesProvider` (`FutureProvider<List<GameSummary>>`) — wyniki szukajki po całej bibliotece, tylko sortowanie. **Nie** zależy już od `selectedSystemProvider` ani `installedOnlyProvider`; te dwa providery zostają w pliku do Task 12 (stary `LibraryScreen`).
  - `sortAndFilter` znika (zastąpione przez `sortGames` + `applyFilter`).

- [ ] **Step 1: Testy**

Zastąp `app/test/core/sorting_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter_test/flutter_test.dart';

GameSummary g(int id, String title, [String system = 'x']) => GameSummary(
      id: id,
      title: title,
      systemCode: system,
      hasCover: false,
      totalSize: 1,
    );

void main() {
  final games = [g(1, 'Zelda'), g(3, 'Aero'), g(2, 'Mario')];

  test('title sort', () {
    expect(
      sortGames(games, LibrarySort.title).map((e) => e.title).toList(),
      ['Aero', 'Mario', 'Zelda'],
    );
  });

  test('recently added sort', () {
    expect(
      sortGames(games, LibrarySort.recentlyAdded).map((e) => e.id).toList(),
      [3, 2, 1],
    );
  });

  test('filters: all / installed / updatable', () {
    expect(applyFilter(games, SystemFilter.all, {}, {}), hasLength(3));
    expect(
      applyFilter(games, SystemFilter.installed, {2}, {}).single.title,
      'Mario',
    );
    expect(
      applyFilter(games, SystemFilter.updatable, {2}, {3}).single.title,
      'Aero',
    );
  });
}
```

Nowy `app/test/features/shelves_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

GameSummary g(int id, String title, String system) => GameSummary(
      id: id,
      title: title,
      systemCode: system,
      hasCover: false,
      totalSize: 1,
    );

const systems = [
  SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 2),
  SystemModel(id: 2, code: 'psx', name: 'PSX', gameCount: 1),
  SystemModel(id: 3, code: 'gba', name: 'GBA', gameCount: 0),
];

void main() {
  final games = [
    for (var i = 1; i <= 12; i++) g(i, 'S$i', 'snes'),
    g(20, 'Tekken', 'psx'),
  ];

  test('buildShelves: recent, installed, per-system in API order', () {
    final shelves = buildShelves(games, systems, {3, 20}, LibrarySort.title);
    expect(shelves.recent.map((e) => e.id).take(3).toList(), [20, 12, 11]);
    expect(shelves.recent, hasLength(10));
    expect(shelves.installed.map((e) => e.title).toList(), ['S3', 'Tekken']);
    expect(shelves.systems.map((s) => s.system.code).toList(),
        ['snes', 'psx', 'gba']);
    expect(shelves.systems.first.games, hasLength(12));
    expect(shelves.systems.last.games, isEmpty);
  });

  test('IdSet marks and unmarks', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ids = container.read(updatableIdsProvider.notifier);
    ids.mark(1, installed: true);
    ids.mark(1, installed: true);
    expect(container.read(updatableIdsProvider), {1});
    ids.mark(1, installed: false);
    expect(container.read(updatableIdsProvider), isEmpty);
  });

  test('systemFilter provider selects', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(systemFilterProvider.notifier).select(SystemFilter.updatable);
    expect(container.read(systemFilterProvider), SystemFilter.updatable);
  });

  test('providers derive from the snapshot', () async {
    final container = ProviderContainer(
      overrides: [
        librarySnapshotProvider.overrideWith(
          (ref) async => LibrarySnapshot(
            systems: systems,
            games: games,
            fromCache: false,
            previousIds: const {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(installedIdsProvider.notifier).mark(3, installed: true);
    container.read(systemFilterProvider.notifier).select(SystemFilter.installed);
    expect(
      (await container.read(systemGamesProvider('snes').future)).single.id,
      3,
    );
    container.read(searchQueryProvider.notifier).update('tek');
    expect((await container.read(gamesProvider.future)).single.id, 20);
    final shelves = await container.read(homeShelvesProvider.future);
    expect(shelves.installed.single.id, 3);
  });
}
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd app && flutter test test/core/sorting_test.dart test/features/shelves_test.dart`

- [ ] **Step 3: Implementacja**

W `providers.dart` zastąp blok od `class InstalledOnly` do końca pliku (zachowaj wszystko powyżej: cache, snapshot, `isOfflineProvider`, `systemsProvider`, `SelectedSystem`, `SearchQuery`, `LibrarySort`, `SortOrder`). `InstalledOnly`/`installedOnlyProvider` zostaw (stary ekran), ale nie używaj.

```dart
/// Zbiór id — jeden typ dla „na urządzeniu" i „do aktualizacji"; zasilany
/// przez odznaki na kafelkach, gdy rozwiążą stan lokalny.
class IdSet extends Notifier<Set<int>> {
  @override
  Set<int> build() => {};

  void mark(int id, {required bool installed}) {
    if (installed == state.contains(id)) return;
    final next = {...state};
    if (installed) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = next;
  }
}

final installedIdsProvider = NotifierProvider<IdSet, Set<int>>(IdSet.new);
final updatableIdsProvider = NotifierProvider<IdSet, Set<int>>(IdSet.new);

enum SystemFilter { all, installed, updatable }

class SystemFilterState extends Notifier<SystemFilter> {
  @override
  SystemFilter build() => SystemFilter.all;

  void select(SystemFilter filter) => state = filter;
}

final systemFilterProvider =
    NotifierProvider<SystemFilterState, SystemFilter>(SystemFilterState.new);

List<GameSummary> sortGames(List<GameSummary> games, LibrarySort sort) {
  final out = [...games];
  out.sort(
    switch (sort) {
      LibrarySort.title => (a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      LibrarySort.recentlyAdded => (a, b) => b.id.compareTo(a.id),
    },
  );
  return out;
}

List<GameSummary> applyFilter(
  List<GameSummary> games,
  SystemFilter filter,
  Set<int> installed,
  Set<int> updatable,
) =>
    switch (filter) {
      SystemFilter.all => games,
      SystemFilter.installed =>
        [for (final g in games) if (installed.contains(g.id)) g],
      SystemFilter.updatable =>
        [for (final g in games) if (updatable.contains(g.id)) g],
    };

class SystemShelf {
  const SystemShelf({required this.system, required this.games});

  final SystemModel system;
  final List<GameSummary> games;
}

class HomeShelves {
  const HomeShelves({
    required this.recent,
    required this.installed,
    required this.systems,
  });

  final List<GameSummary> recent;
  final List<GameSummary> installed;
  final List<SystemShelf> systems;
}

const kRecentShelfSize = 10;

HomeShelves buildShelves(
  List<GameSummary> games,
  List<SystemModel> systems,
  Set<int> installedIds,
  LibrarySort sort,
) {
  final recent =
      sortGames(games, LibrarySort.recentlyAdded).take(kRecentShelfSize);
  final installed = sortGames(
    [for (final g in games) if (installedIds.contains(g.id)) g],
    sort,
  );
  return HomeShelves(
    recent: recent.toList(),
    installed: installed,
    systems: [
      for (final system in systems)
        SystemShelf(
          system: system,
          games: sortGames(
            [for (final g in games) if (g.systemCode == system.code) g],
            sort,
          ),
        ),
    ],
  );
}

final homeShelvesProvider = FutureProvider<HomeShelves>((ref) async {
  final snapshot = await ref.watch(librarySnapshotProvider.future);
  return buildShelves(
    snapshot.games,
    snapshot.systems,
    ref.watch(installedIdsProvider),
    ref.watch(sortProvider),
  );
});

/// Gry jednego systemu po chipie filtra i sortowaniu.
final systemGamesProvider =
    FutureProvider.family<List<GameSummary>, String>((ref, code) async {
  final snapshot = await ref.watch(librarySnapshotProvider.future);
  final own = [for (final g in snapshot.games) if (g.systemCode == code) g];
  return sortGames(
    applyFilter(
      own,
      ref.watch(systemFilterProvider),
      ref.watch(installedIdsProvider),
      ref.watch(updatableIdsProvider),
    ),
    ref.watch(sortProvider),
  );
});

/// Wyniki szukajki po całej bibliotece (ekran główny).
final gamesProvider = FutureProvider<List<GameSummary>>((ref) async {
  final snapshot = await ref.watch(librarySnapshotProvider.future);
  final search = ref.watch(searchQueryProvider).trim().toLowerCase();
  return sortGames(
    [
      for (final g in snapshot.games)
        if (search.isEmpty || g.title.toLowerCase().contains(search)) g,
    ],
    ref.watch(sortProvider),
  );
});
```

Stary `LibraryScreen` używa `installedOnlyProvider` i `selectedSystemProvider` tylko do odczytu/zapisu stanu — nadal się kompiluje. Test `library_screen_test.dart` `installedIds tracks games…` przechodzi bez zmian (ten sam `mark`).

- [ ] **Step 4: Testy**

Run: `cd app && flutter test && flutter analyze`
Expected: PASS (stare testy biblioteki też, bo `gamesProvider` jest w nich nadpisywany).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/library/providers.dart app/test/core/sorting_test.dart app/test/features/shelves_test.dart
git commit -m "feat(library): półki, filtr systemu i sortowanie jako czyste funkcje"
```

---

### Task 5: Widgety biblioteki — okładka, odznaka, kafel, półka, grid, szukajka, sortowanie

**Files:**
- Modify: `app/lib/features/library/widgets/cover_image.dart`
- Create: `app/lib/features/library/widgets/install_badge.dart`, `game_tile.dart`, `shelf.dart`, `games_grid.dart`, `search_field.dart`, `sort_menu.dart`
- Test: `app/test/features/library_widgets_test.dart` (zastąp)

**Interfaces:**
- Consumes: `apiClientProvider`, `localStateProvider(id)`, `installedIdsProvider`, `updatableIdsProvider`, `sortProvider`, `searchQueryProvider`, `formatBytes`.
- Produces:
  - `CoverImage({title, url, headers, hasCover, fit = BoxFit.contain})` — jak dziś; placeholder w nowych kolorach; eksportuje `coverPlaceholderGradient`.
  - `InstallBadge({required int gameId})` — odznaka; oznacza gry w `installedIdsProvider` i `updatableIdsProvider`.
  - `GameTile({required GameSummary game, bool hero = true})` — kafel gridu (okładka 3:4 z Hero `cover-{id}`, tytuł 2 linie, rozmiar); tap → `context.go('/game/{id}')`.
  - `ShelfCard({required GameSummary game, double width = 96})` — kafel półki bez Hero, tytuł 1 linia.
  - `Shelf({required String title, required List<GameSummary> games, String? trailing, VoidCallback? onSeeAll, double cardWidth = 96, int limit = 12})` — nagłówek + poziomy `ListView.builder`; gdy `games.length > limit`, ostatni kafel „Wszystkie (N)" wywołuje `onSeeAll`.
  - `GamesGrid({required List<GameSummary> games, EdgeInsets padding = const EdgeInsets.fromLTRB(16, 12, 16, kListBottomPad)})` — `GridView.builder` 2 kolumny.
  - `SearchField({required String hint, required ValueChanged<String> onChanged, TextEditingController? controller})`.
  - `SortMenu()` — `PopupMenuButton<LibrarySort>` na `sortProvider`, ikona `Icons.sort` w pastylce jak `CircleIconButton`.

- [ ] **Step 1: Testy**

```dart
// app/test/features/library_widgets_test.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/library/widgets/cover_image.dart';
import 'package:droplet/features/library/widgets/game_tile.dart';
import 'package:droplet/features/library/widgets/games_grid.dart';
import 'package:droplet/features/library/widgets/install_badge.dart';
import 'package:droplet/features/library/widgets/search_field.dart';
import 'package:droplet/features/library/widgets/shelf.dart';
import 'package:droplet/features/library/widgets/sort_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GameSummary g(int id, String title, {bool cover = false}) => GameSummary(
      id: id,
      title: title,
      systemCode: 'snes',
      hasCover: cover,
      totalSize: 1024,
    );

LocalGameState local(InstallStatus status, {bool update = false}) =>
    LocalGameState(
      status: status,
      updateAvailable: update,
      missing: const [],
      presentPaths: const [],
    );

GoRouter _router(Widget home) => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(body: home),
          routes: [
            GoRoute(
              path: 'game/:id',
              builder: (_, s) =>
                  Scaffold(body: Text('Gra ${s.pathParameters['id']}')),
            ),
          ],
        ),
      ],
    );

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://nas:8000', token: 't'),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: _router(home)),
    );

void main() {
  testWidgets('CoverImage: placeholder without cover, network with cover', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Row(
          children: [
            SizedBox(
              width: 100,
              height: 130,
              child: CoverImage(
                title: 'Mario',
                url: '',
                headers: {},
                hasCover: false,
              ),
            ),
            SizedBox(
              width: 100,
              height: 130,
              child: CoverImage(
                title: 'Zelda',
                url: 'http://nas:8000/c.png',
                headers: {},
                hasCover: true,
              ),
            ),
          ],
        ),
      ),
    );
    expect(find.text('Mario'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('GameTile shows title and size and navigates', (tester) async {
    await tester.pumpWidget(
      _app(
        SizedBox(width: 180, height: 300, child: GameTile(game: g(7, 'Mario'))),
        overrides: [
          localStateProvider(7).overrideWith(
            (ref) async => local(InstallStatus.none),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mario'), findsWidgets);
    expect(find.text('1.0 KB'), findsOneWidget);
    await tester.tap(find.byType(GameTile));
    await tester.pumpAndSettle();
    expect(find.text('Gra 7'), findsOneWidget);
  });

  testWidgets('InstallBadge reflects state and feeds id sets', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      _app(
        Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const Row(
              children: [
                InstallBadge(gameId: 1),
                InstallBadge(gameId: 2),
                InstallBadge(gameId: 3),
                InstallBadge(gameId: 4),
              ],
            );
          },
        ),
        overrides: [
          localStateProvider(1).overrideWith(
            (ref) async => local(InstallStatus.installed),
          ),
          localStateProvider(2).overrideWith(
            (ref) async => local(InstallStatus.partial, update: true),
          ),
          localStateProvider(3).overrideWith(
            (ref) async => local(InstallStatus.partial),
          ),
          localStateProvider(4).overrideWith(
            (ref) async => local(InstallStatus.none),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    expect(container.read(installedIdsProvider), {1, 2, 3});
    expect(container.read(updatableIdsProvider), {2});
  });

  testWidgets('Shelf caps cards and offers "Wszystkie"', (tester) async {
    var seeAll = 0;
    final games = [for (var i = 1; i <= 14; i++) g(i, 'G$i')];
    await tester.pumpWidget(
      _app(
        Shelf(
          title: 'SNES',
          trailing: '14 ›',
          games: games,
          onSeeAll: () => seeAll++,
        ),
        overrides: [
          for (final game in games)
            localStateProvider(game.id).overrideWith(
              (ref) async => local(InstallStatus.none),
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SNES'), findsOneWidget);
    await tester.tap(find.text('14 ›'));
    expect(seeAll, 1);
    await tester.drag(find.byType(ListView), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(find.text('Wszystkie (14)'), findsOneWidget);
    await tester.tap(find.text('Wszystkie (14)'));
    expect(seeAll, 2);
    expect(find.text('G13'), findsNothing);
  });

  testWidgets('Shelf without overflow has no "Wszystkie" tile', (tester) async {
    await tester.pumpWidget(
      _app(
        Shelf(title: 'PSX', games: [g(1, 'Tekken')]),
        overrides: [
          localStateProvider(1).overrideWith(
            (ref) async => local(InstallStatus.none),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Wszystkie'), findsNothing);
    expect(find.text('Tekken'), findsOneWidget);
  });

  testWidgets('GamesGrid lays out tiles', (tester) async {
    await tester.pumpWidget(
      _app(
        GamesGrid(games: [g(1, 'A'), g(2, 'B')]),
        overrides: [
          for (final id in [1, 2])
            localStateProvider(id).overrideWith(
              (ref) async => local(InstallStatus.none),
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsNWidgets(2));
  });

  testWidgets('SearchField forwards input', (tester) async {
    String? last;
    await tester.pumpWidget(
      _app(SearchField(hint: 'Szukaj', onChanged: (v) => last = v)),
    );
    await tester.enterText(find.byType(TextField), 'tek');
    expect(last, 'tek');
    expect(find.text('Szukaj'), findsOneWidget);
  });

  testWidgets('SortMenu switches the sort provider', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      _app(
        Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const SortMenu();
          },
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ostatnio dodane'));
    await tester.pumpAndSettle();
    expect(container.read(sortProvider), LibrarySort.recentlyAdded);
  });
}
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd app && flutter test test/features/library_widgets_test.dart`

- [ ] **Step 3: CoverImage**

W `cover_image.dart` zmień tylko `_Placeholder`:

```dart
const coverPlaceholderGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF242B45), Color(0xFF161A2C)],
);

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(gradient: coverPlaceholderGradient),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kTextDim,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
}
```

- [ ] **Step 4: InstallBadge**

```dart
// app/lib/features/library/widgets/install_badge.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/tokens.dart';
import '../../../core/downloads/local_state.dart';
import '../../game/providers.dart';
import '../providers.dart';

/// Odznaka w rogu okładki; przy okazji zasila zbiory id dla filtrów.
class InstallBadge extends ConsumerWidget {
  const InstallBadge({super.key, required this.gameId});

  final int gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(localStateProvider(gameId)).value;
    if (local != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(installedIdsProvider.notifier).mark(
              gameId,
              installed: local.status != InstallStatus.none,
            );
        ref
            .read(updatableIdsProvider.notifier)
            .mark(gameId, installed: local.updateAvailable);
      });
    }
    if (local == null || local.status == InstallStatus.none) {
      return const SizedBox.shrink();
    }
    final (icon, bg, fg) = switch ((local.status, local.updateAvailable)) {
      (_, true) => (Icons.arrow_downward_rounded, kBgBottom, kAccent),
      (InstallStatus.installed, _) => (Icons.check_rounded, kAccent, kBgBottom),
      _ => (Icons.more_horiz_rounded, kBgBottom, kTextDim),
    };
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: fg.withValues(alpha: 0.6)),
      ),
      child: Icon(icon, size: 14, color: fg),
    );
  }
}
```

- [ ] **Step 5: GameTile i ShelfCard**

```dart
// app/lib/features/library/widgets/game_tile.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/api/models.dart';
import '../../../core/format.dart';
import '../../../core/session/providers.dart';
import 'cover_image.dart';
import 'install_badge.dart';

/// Okładka 3:4 z odznaką — wspólny kawałek kafla gridu i kafla półki.
class CoverThumb extends ConsumerWidget {
  const CoverThumb({super.key, required this.game, this.hero = false});

  final GameSummary game;
  final bool hero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tylko gra z okładką potrzebuje klienta — grid bez okładek nie strzela
    // po HTTP i nie wymaga sesji w testach.
    final client = game.hasCover ? ref.watch(apiClientProvider) : null;
    Widget image = CoverImage(
      title: game.title,
      url: client?.coverUrl(game.id) ?? '',
      headers: client?.authHeaders ?? const {},
      hasCover: game.hasCover,
    );
    if (hero) image = Hero(tag: 'cover-${game.id}', child: image);
    return ClipRRect(
      borderRadius: BorderRadius.circular(kRadiusCover),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: kGlassBorder),
                borderRadius: BorderRadius.circular(kRadiusCover),
              ),
              position: DecorationPosition.foreground,
              child: image,
            ),
            Positioned(
              right: 6,
              top: 6,
              child: InstallBadge(gameId: game.id),
            ),
          ],
        ),
      ),
    );
  }
}

class GameTile extends StatelessWidget {
  const GameTile({super.key, required this.game, this.hero = true});

  final GameSummary game;
  final bool hero;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(kRadiusCover),
        onTap: () => context.go('/game/${game.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverThumb(game: game, hero: hero),
            const SizedBox(height: 8),
            Text(
              game.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatBytes(game.totalSize),
              style: const TextStyle(color: kTextDim, fontSize: 12),
            ),
          ],
        ),
      );
}

class ShelfCard extends StatelessWidget {
  const ShelfCard({super.key, required this.game, this.width = 96});

  final GameSummary game;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusCover),
          onTap: () => context.go('/game/${game.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverThumb(game: game),
              const SizedBox(height: 6),
              Text(
                game.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: kText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}
```

- [ ] **Step 6: Shelf, GamesGrid, SearchField, SortMenu**

```dart
// app/lib/features/library/widgets/shelf.dart
import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../app/widgets/glass_panel.dart';
import '../../../core/api/models.dart';
import 'game_tile.dart';

class Shelf extends StatelessWidget {
  const Shelf({
    super.key,
    required this.title,
    required this.games,
    this.trailing,
    this.onSeeAll,
    this.cardWidth = 96,
    this.limit = 12,
  });

  final String title;
  final List<GameSummary> games;
  final String? trailing;
  final VoidCallback? onSeeAll;
  final double cardWidth;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final shown = games.take(limit).toList();
    final overflow = games.length > limit;
    final cardHeight = cardWidth * 4 / 3 + 26;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: kText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (trailing != null)
                GestureDetector(
                  onTap: onSeeAll,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    trailing!,
                    style: const TextStyle(color: kTextDim, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: shown.length + (overflow ? 1 : 0),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: i < shown.length
                  ? ShelfCard(game: shown[i], width: cardWidth)
                  : SizedBox(
                      width: cardWidth,
                      child: GlassPanel(
                        onTap: onSeeAll,
                        padding: EdgeInsets.zero,
                        child: Center(
                          child: Text(
                            'Wszystkie (${games.length})',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: kAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
```

```dart
// app/lib/features/library/widgets/games_grid.dart
import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/api/models.dart';
import 'game_tile.dart';

class GamesGrid extends StatelessWidget {
  const GamesGrid({
    super.key,
    required this.games,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, kListBottomPad),
  });

  final List<GameSummary> games;
  final EdgeInsets padding;

  static const delegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    crossAxisSpacing: 14,
    mainAxisSpacing: 18,
    childAspectRatio: 0.58,
  );

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: padding,
        gridDelegate: delegate,
        itemCount: games.length,
        itemBuilder: (_, i) => GameTile(game: games[i]),
      );
}
```

```dart
// app/lib/features/library/widgets/search_field.dart
import 'package:flutter/material.dart';

import '../../../app/tokens.dart';

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: kText, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, color: kTextDim, size: 20),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: kGlassBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: kGlassBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: kAccent),
          ),
        ),
      );
}
```

```dart
// app/lib/features/library/widgets/sort_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/tokens.dart';
import '../providers.dart';

/// Sortowanie za jedną ikoną — bibliotekę przegląda się częściej, niż sortuje.
class SortMenu extends ConsumerWidget {
  const SortMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<LibrarySort>(
        tooltip: 'Sortowanie',
        initialValue: ref.watch(sortProvider),
        onSelected: (v) => ref.read(sortProvider.notifier).select(v),
        itemBuilder: (_) => const [
          PopupMenuItem(value: LibrarySort.title, child: Text('Alfabetycznie')),
          PopupMenuItem(
            value: LibrarySort.recentlyAdded,
            child: Text('Ostatnio dodane'),
          ),
        ],
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: kGlassBorder),
          ),
          child: const Icon(Icons.sort, size: 20, color: kText),
        ),
      );
}
```

- [ ] **Step 7: Testy**

Run: `cd app && flutter test test/features/library_widgets_test.dart && flutter analyze`
Expected: PASS. Uwaga na test `Shelf caps cards`: `ListView` w teście musi być jedyny — `Shelf` renderuje jeden.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/library/widgets app/test/features/library_widgets_test.dart
git commit -m "feat(library): kafle, półka, grid, szukajka i sortowanie w stylu Glass"
```

---

### Task 6: Ekran główny z półkami

**Files:**
- Create: `app/lib/features/home/home_screen.dart`
- Test: `app/test/features/home_screen_test.dart`

**Interfaces:**
- Consumes: `homeShelvesProvider`, `gamesProvider`, `librarySnapshotProvider`, `isOfflineProvider`, `searchQueryProvider`, `newGameCount` (z `providers.dart`), `Shelf`, `GamesGrid`, `SearchField`, `SortMenu`, `PulseBox`, `PrimaryButton`, `humanizeError`.
- Produces: `class HomeScreen extends ConsumerStatefulWidget`. Nawigacja: nagłówek półki systemu → `context.go('/system/{code}')`.

- [ ] **Step 1: Testy**

```dart
// app/test/features/home_screen_test.dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/home/home_screen.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/library/widgets/games_grid.dart';
import 'package:droplet/features/library/widgets/shelf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GameSummary g(int id, String title, String system) => GameSummary(
      id: id,
      title: title,
      systemCode: system,
      hasCover: false,
      totalSize: 5,
    );

final games = [g(1, 'Super Mario World', 'snes'), g(2, 'Tekken', 'psx')];
const systems = [
  SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 1),
  SystemModel(id: 2, code: 'psx', name: 'PSX', gameCount: 1),
];

const _none = LocalGameState(
  status: InstallStatus.none,
  updateAvailable: false,
  missing: [],
  presentPaths: [],
);

LibrarySnapshot snap({bool fromCache = false, Set<int> previous = const {1, 2}}) =>
    LibrarySnapshot(
      systems: systems,
      games: games,
      fromCache: fromCache,
      previousIds: previous,
    );

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const HomeScreen(),
          routes: [
            GoRoute(
              path: 'system/:code',
              builder: (_, s) =>
                  Scaffold(body: Text('System ${s.pathParameters['code']}')),
            ),
            GoRoute(
              path: 'game/:id',
              builder: (_, s) =>
                  Scaffold(body: Text('Gra ${s.pathParameters['id']}')),
            ),
          ],
        ),
      ],
    );

Widget _app({List<Override> overrides = const []}) => ProviderScope(
      overrides: [
        librarySnapshotProvider.overrideWith((ref) async => snap()),
        localStateProvider(1).overrideWith((ref) async => _none),
        localStateProvider(2).overrideWith((ref) async => _none),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

void main() {
  testWidgets('shelves: recent + per system, header opens the system', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Droplet'), findsOneWidget);
    expect(find.text('Ostatnio dodane'), findsOneWidget);
    expect(find.text('Na urządzeniu'), findsNothing);
    expect(find.text('SNES'), findsOneWidget);
    expect(find.text('Super Mario World'), findsWidgets);
    await tester.tap(find.text('SNES'));
    await tester.pumpAndSettle();
    expect(find.text('System snes'), findsOneWidget);
  });

  testWidgets('installed shelf appears when something is on disk', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          localStateProvider(2).overrideWith(
            (ref) async => const LocalGameState(
              status: InstallStatus.installed,
              updateAvailable: false,
              missing: [],
              presentPaths: ['/x'],
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Na urządzeniu'), findsOneWidget);
  });

  testWidgets('typing swaps shelves for a results grid', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tek');
    await tester.pumpAndSettle();
    expect(find.byType(Shelf), findsNothing);
    expect(find.byType(GamesGrid), findsOneWidget);
    expect(find.text('Wyniki · 1'), findsOneWidget);
    expect(find.text('Tekken'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Brak wyników'), findsOneWidget);
  });

  testWidgets('offline pill', (tester) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          librarySnapshotProvider.overrideWith(
            (ref) async => snap(fromCache: true),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Tryb offline — pokazuję ostatnio pobraną bibliotekę'),
      findsOneWidget,
    );
  });

  testWidgets('error state retries', (tester) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          librarySnapshotProvider.overrideWith(
            (ref) async => throw StateError('x'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
    await tester.tap(find.text('Ponów'));
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
  });

  testWidgets('empty library', (tester) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          librarySnapshotProvider.overrideWith(
            (ref) async => const LibrarySnapshot(
              systems: [],
              games: [],
              fromCache: false,
              previousIds: {},
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nic tu nie ma'), findsOneWidget);
  });

  testWidgets('new games are announced once', (tester) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          librarySnapshotProvider.overrideWith(
            (ref) async => snap(previous: {1}),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nowe w bibliotece: 1 gier'), findsOneWidget);
  });

  testWidgets('loading shows skeleton', (tester) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          librarySnapshotProvider.overrideWith(
            (ref) => Future.delayed(const Duration(days: 1), snap),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(HomeSkeleton), findsOneWidget);
  });
}
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd app && flutter test test/features/home_screen_test.dart`

- [ ] **Step 3: Implementacja**

```dart
// app/lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../app/widgets/primary_button.dart';
import '../../app/widgets/pulse_box.dart';
import '../../core/errors.dart';
import '../library/providers.dart';
import '../library/widgets/games_grid.dart';
import '../library/widgets/search_field.dart';
import '../library/widgets/shelf.dart';
import '../library/widgets/sort_menu.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  var _announcedNew = false;

  /// Raz na snapshot: co przyniosło odświeżenie.
  void _announceNewGames(LibrarySnapshot snapshot) {
    if (_announcedNew) return;
    _announcedNew = true;
    final count = newGameCount(
      snapshot.previousIds,
      [for (final g in snapshot.games) g.id],
    );
    if (count == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nowe w bibliotece: $count gier')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(librarySnapshotProvider);
    if (snapshot.hasValue) _announceNewGames(snapshot.requireValue);
    final query = ref.watch(searchQueryProvider).trim();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _Header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SearchField(
                hint: 'Szukaj w bibliotece',
                onChanged: (v) =>
                    ref.read(searchQueryProvider.notifier).update(v),
              ),
            ),
            if (ref.watch(isOfflineProvider)) const _OfflinePill(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(librarySnapshotProvider),
                child: snapshot.when(
                  loading: () => const HomeSkeleton(),
                  error: (e, _) => _Message(
                    title: humanizeError(e),
                    action: 'Ponów',
                    onAction: () => ref.invalidate(librarySnapshotProvider),
                  ),
                  data: (s) => s.games.isEmpty
                      ? const _Message(
                          title: 'Nic tu nie ma',
                          subtitle: 'Uruchom skan na serwerze.',
                        )
                      : query.isEmpty
                          ? const _Shelves()
                          : const _Results(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Droplet',
                style: TextStyle(
                  color: kText,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
            ),
            SortMenu(),
          ],
        ),
      );
}

class _OfflinePill extends StatelessWidget {
  const _OfflinePill();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kGlass,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kGlassBorder),
        ),
        child: const Row(
          children: [
            Icon(Icons.cloud_off, size: 16, color: kTextDim),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tryb offline — pokazuję ostatnio pobraną bibliotekę',
                style: TextStyle(color: kTextDim, fontSize: 12),
              ),
            ),
          ],
        ),
      );
}

class _Shelves extends ConsumerWidget {
  const _Shelves();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelves = ref.watch(homeShelvesProvider).value;
    if (shelves == null) return const HomeSkeleton();
    return ListView(
      padding: const EdgeInsets.only(bottom: kListBottomPad),
      children: [
        Shelf(title: 'Ostatnio dodane', games: shelves.recent, cardWidth: 120),
        if (shelves.installed.isNotEmpty)
          Shelf(title: 'Na urządzeniu', games: shelves.installed),
        for (final shelf in shelves.systems)
          if (shelf.games.isNotEmpty)
            Shelf(
              title: shelf.system.name,
              trailing: '${shelf.games.length} ›',
              games: shelf.games,
              onSeeAll: () => context.go('/system/${shelf.system.code}'),
            ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(gamesProvider).value ?? const [];
    if (games.isEmpty) {
      return const _Message(
        title: 'Brak wyników',
        subtitle: 'Spróbuj innego tytułu.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            'Wyniki · ${games.length}',
            style: const TextStyle(
              color: kText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: GamesGrid(games: games)),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kText, fontSize: 17),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextDim),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: 160,
                child: PrimaryButton(label: action!, onPressed: onAction),
              ),
            ),
          ],
        ],
      );
}

/// Trzy półki z pulsujących bloków — układ stoi, zanim przyjdą dane.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 0, kListBottomPad),
        children: [
          for (var s = 0; s < 3; s++) ...[
            const PulseBox(height: 18, width: 140),
            const SizedBox(height: 10),
            SizedBox(
              height: 154,
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: PulseBox(width: 96, height: 128),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      );
}
```

- [ ] **Step 4: Testy**

Run: `cd app && flutter test test/features/home_screen_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/home app/test/features/home_screen_test.dart
git commit -m "feat(home): ekran główny z półkami i gridem wyników"
```

---

### Task 7: Widok systemu

**Files:**
- Create: `app/lib/features/system/system_screen.dart`
- Test: `app/test/features/system_screen_test.dart`

**Interfaces:**
- Consumes: `systemsProvider`, `systemGamesProvider(code)`, `systemFilterProvider`, `installedIdsProvider`, `CircleIconButton`, `SearchField`, `SortMenu`, `GamesGrid`, `PulseBox`.
- Produces: `class SystemScreen extends ConsumerStatefulWidget { const SystemScreen({required String code}) }`. Wstecz: `CircleIconButton(key: Key('back-button'), icon: Icons.arrow_back_rounded, onPressed: () => context.pop())`. Szukajka po systemie to lokalny stan ekranu; `filterByQuery(List<GameSummary>, String)` to publiczna czysta funkcja.

- [ ] **Step 1: Testy**

```dart
// app/test/features/system_screen_test.dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/library/widgets/game_tile.dart';
import 'package:droplet/features/system/system_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GameSummary g(int id, String title) => GameSummary(
      id: id,
      title: title,
      systemCode: 'snes',
      hasCover: false,
      totalSize: 5,
    );

LocalGameState local(InstallStatus s, {bool update = false}) => LocalGameState(
      status: s,
      updateAvailable: update,
      missing: const [],
      presentPaths: const [],
    );

const systems = [
  SystemModel(id: 1, code: 'snes', name: 'Super Nintendo', gameCount: 3),
];

GoRouter _router() => GoRouter(
      initialLocation: '/system/snes',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: 'system/:code',
              builder: (_, s) => SystemScreen(code: s.pathParameters['code']!),
            ),
            GoRoute(
              path: 'game/:id',
              builder: (_, s) =>
                  Scaffold(body: Text('Gra ${s.pathParameters['id']}')),
            ),
          ],
        ),
      ],
    );

Widget _app(List<GameSummary> games, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        librarySnapshotProvider.overrideWith(
          (ref) async => LibrarySnapshot(
            systems: systems,
            games: games,
            fromCache: false,
            previousIds: const {},
          ),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

void main() {
  final games = [g(1, 'Mario'), g(2, 'Zelda'), g(3, 'Metroid')];
  final states = [
    localStateProvider(1).overrideWith(
      (ref) async => local(InstallStatus.installed),
    ),
    localStateProvider(2).overrideWith(
      (ref) async => local(InstallStatus.partial, update: true),
    ),
    localStateProvider(3).overrideWith((ref) async => local(InstallStatus.none)),
  ];

  testWidgets('header, counts and back', (tester) async {
    await tester.pumpWidget(_app(games, overrides: states));
    await tester.pumpAndSettle();
    expect(find.text('Super Nintendo'), findsOneWidget);
    expect(find.text('3 gry · 2 na urządzeniu'), findsOneWidget);
    expect(find.byType(GameTile), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('chips filter installed and updatable', (tester) async {
    await tester.pumpWidget(_app(games, overrides: states));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Na urządzeniu'));
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsNWidgets(2));
    await tester.tap(find.text('Do aktualizacji'));
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsOneWidget);
    expect(find.text('Zelda'), findsWidgets);
    await tester.tap(find.text('Wszystkie'));
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsNWidgets(3));
  });

  testWidgets('search narrows within the system', (tester) async {
    await tester.pumpWidget(_app(games, overrides: states));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'met');
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.pumpAndSettle();
    expect(find.text('Nic nie pasuje'), findsOneWidget);
  });

  testWidgets('unknown system code shows a message', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          librarySnapshotProvider.overrideWith(
            (ref) async => const LibrarySnapshot(
              systems: [],
              games: [],
              fromCache: false,
              previousIds: {},
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nieznany system'), findsOneWidget);
  });

  testWidgets('loading skeleton and error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          librarySnapshotProvider.overrideWith(
            (ref) async => throw StateError('x'),
          ),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
  });

  test('filterByQuery is case-insensitive', () {
    expect(filterByQuery(games, 'MAR').single.title, 'Mario');
    expect(filterByQuery(games, '  '), hasLength(3));
  });
}
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd app && flutter test test/features/system_screen_test.dart`

- [ ] **Step 3: Implementacja**

```dart
// app/lib/features/system/system_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../app/widgets/circle_icon_button.dart';
import '../../app/widgets/primary_button.dart';
import '../../app/widgets/pulse_box.dart';
import '../../core/api/models.dart';
import '../../core/errors.dart';
import '../library/providers.dart';
import '../library/widgets/games_grid.dart';
import '../library/widgets/search_field.dart';
import '../library/widgets/sort_menu.dart';

List<GameSummary> filterByQuery(List<GameSummary> games, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return games;
  return [for (final g in games) if (g.title.toLowerCase().contains(q)) g];
}

class SystemScreen extends ConsumerStatefulWidget {
  const SystemScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends ConsumerState<SystemScreen> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final systems = ref.watch(systemsProvider);
    final games = ref.watch(systemGamesProvider(widget.code));
    final system = systems.value?.where((s) => s.code == widget.code).firstOrNull;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(system: system, code: widget.code),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SearchField(
                hint: 'Szukaj w ${system?.name ?? widget.code}',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const _FilterChips(),
            Expanded(
              child: systems.when(
                loading: () => const _Skeleton(),
                error: (e, _) => _Message(
                  humanizeError(e),
                  action: 'Ponów',
                  onAction: () => ref.invalidate(librarySnapshotProvider),
                ),
                data: (_) {
                  if (system == null) return const _Message('Nieznany system');
                  final list = filterByQuery(games.value ?? const [], _query);
                  if (list.isEmpty) return const _Message('Nic nie pasuje');
                  return GamesGrid(games: list);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.system, required this.code});

  final SystemModel? system;
  final String code;

  static String _plural(int n) => switch (n % 10) {
        1 when n % 100 != 11 => '$n gra',
        2 || 3 || 4 when n % 100 < 10 || n % 100 > 20 => '$n gry',
        _ => '$n gier',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(librarySnapshotProvider).value?.games ?? const [];
    final own = [for (final g in all) if (g.systemCode == code) g];
    final installed = ref.watch(installedIdsProvider);
    final onDevice = own.where((g) => installed.contains(g.id)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 4),
      child: Row(
        children: [
          CircleIconButton(
            key: const Key('back-button'),
            icon: Icons.arrow_back_rounded,
            tooltip: 'Wstecz',
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  system?.name ?? code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kText,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '${_plural(own.length)} · $onDevice na urządzeniu',
                  style: const TextStyle(color: kTextDim, fontSize: 12),
                ),
              ],
            ),
          ),
          const SortMenu(),
        ],
      ),
    );
  }
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  static const _labels = {
    SystemFilter.all: 'Wszystkie',
    SystemFilter.installed: 'Na urządzeniu',
    SystemFilter.updatable: 'Do aktualizacji',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(systemFilterProvider);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        children: [
          for (final entry in _labels.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () =>
                    ref.read(systemFilterProvider.notifier).select(entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected == entry.key ? kAccent : kGlass,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected == entry.key ? kAccent : kGlassBorder,
                    ),
                  ),
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      color: selected == entry.key ? kBgBottom : kText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 60),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextDim, fontSize: 15),
          ),
          if (action != null) ...[
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: 160,
                child: PrimaryButton(label: action!, onPressed: onAction),
              ),
            ),
          ],
        ],
      );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, kListBottomPad),
        gridDelegate: GamesGrid.delegate,
        itemCount: 6,
        itemBuilder: (_, __) => const PulseBox(),
      );
}
```

- [ ] **Step 4: Testy**

Run: `cd app && flutter test test/features/system_screen_test.dart && flutter analyze`
Expected: PASS. (`3 gry` z `_plural(3)`; test liczy na ten wynik.)

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/system app/test/features/system_screen_test.dart
git commit -m "feat(system): widok systemu z chipami, szukajką i gridem"
```

---

### Task 8: Karta gry

**Files:**
- Modify: `app/lib/features/game/providers.dart` (+ `freeBytesProvider`)
- Modify: `app/lib/features/game/game_detail_screen.dart` (przepisanie)
- Modify: `app/lib/features/game/delete_dialog.dart` (tylko kolory: `kDialogBg`, `kText`, `kTextDim`, `kAccent` z `tokens.dart`)
- Test: `app/test/features/game_detail_test.dart` (zastąp), `app/test/features/game_actions_test.dart` (dopasuj teksty), `app/test/features/download_flow_test.dart` (dopasuj teksty przycisków)

**Interfaces:**
- Consumes: `gameDetailProvider`, `localStateProvider`, `downloadManagerProvider`, `downloaderPortProvider`, `storageSettingsProvider`, `sessionProvider`, `isOfflineProvider`, `defaultSelection`, `confirmAndDelete`, `CoverImage`, `coverPlaceholderGradient`, `CircleIconButton`, `Pill`, `PrimaryButton`, `SectionLabel`, `GlassPanel`, `PulseBox`.
- Produces: `GameDetailScreen({required int gameId})`; `freeBytesProvider` = `FutureProvider.family<int?, String>((ref, path) => ref.watch(downloaderPortProvider).freeBytes(path))`; publiczne `roleLabels`, `labelFor(GameFileModel)` (bez zmian) i `int bytesToFetch(GameDetail, Set<int> selected, LocalGameState)` (suma rozmiarów zaznaczonych plików, których nie ma na dysku — po nazwie pliku).
- Teksty: pigułki `Zainstalowana` / `Jest aktualizacja` / `Częściowo`; przyciski `Pobierz · X` / `Pobierz aktualizację · X` / `Usuń z urządzenia`; linia `Wolne X · zapis: <dir>` lub `zapis: <dir>`; offline: `Offline — pobieranie niedostępne`.

- [ ] **Step 1: Testy**

Zastąp `app/test/features/game_detail_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/format.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fakes/fake_downloader_port.dart';

const _detail = GameDetail(
  id: 7,
  title: 'Hollow Knight',
  systemCode: 'switch',
  systemName: 'Switch',
  hasCover: false,
  totalSize: 3,
  files: [
    GameFileModel(
      id: 1,
      name: 'hk.nsp',
      relativePath: 'switch/hk.nsp',
      role: FileRole.base,
      discNumber: null,
      version: '',
      size: 1,
    ),
    GameFileModel(
      id: 2,
      name: 'upd.nsp',
      relativePath: 'switch/upd.nsp',
      role: FileRole.update,
      discNumber: null,
      version: 'v196608',
      size: 2,
    ),
  ],
);

const _notInstalled = LocalGameState(
  status: InstallStatus.none,
  updateAvailable: false,
  missing: [],
  presentPaths: [],
);

GoRouter _router() => GoRouter(
      initialLocation: '/game/7',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: 'game/:id',
              builder: (_, s) =>
                  GameDetailScreen(gameId: int.parse(s.pathParameters['id']!)),
            ),
          ],
        ),
      ],
    );

Widget _screen(
  GameDetail detail, {
  LocalGameState local = _notInstalled,
  List<Override> overrides = const [],
  FakeDownloaderPort? port,
}) =>
    ProviderScope(
      overrides: [
        gameDetailProvider(7).overrideWith((ref) async => detail),
        localStateProvider(7).overrideWith((ref) async => local),
        downloaderPortProvider.overrideWithValue(port ?? FakeDownloaderPort()),
        storageSettingsProvider.overrideWith(
          (ref) async => StorageSettings('/roms', const {}),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

void main() {
  test('formatBytes', () {
    expect(formatBytes(500), '500 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(1500000000), '1.4 GB');
  });

  test('bytesToFetch skips files already on disk', () {
    const local = LocalGameState(
      status: InstallStatus.partial,
      updateAvailable: true,
      missing: [],
      presentPaths: ['/roms/switch/hk.nsp'],
    );
    expect(bytesToFetch(_detail, {1, 2}, local), 2);
    expect(bytesToFetch(_detail, {1}, local), 0);
  });

  testWidgets('hero, pills, sections, back button', (tester) async {
    final port = FakeDownloaderPort()..free = 5 * 1024 * 1024 * 1024;
    await tester.pumpWidget(_screen(_detail, port: port));
    await tester.pumpAndSettle();
    expect(find.text('Hollow Knight'), findsWidgets);
    expect(find.text('Switch'), findsOneWidget);
    expect(find.text('Aktualizacja'), findsOneWidget);
    expect(find.text('najnowsza domyślnie'), findsOneWidget);
    expect(find.text('Pobierz · 3 B'), findsOneWidget);
    expect(find.text('Wolne 5.0 GB · zapis: /roms/switch'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.textContaining('v196608'), findsOneWidget);
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('unchecking a file lowers the button size', (tester) async {
    await tester.pumpWidget(_screen(_detail));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    expect(find.text('Pobierz · 1 B'), findsOneWidget);
  });

  testWidgets('unknown free space shows only the directory', (tester) async {
    await tester.pumpWidget(_screen(_detail));
    await tester.pumpAndSettle();
    expect(find.text('zapis: /roms/switch'), findsOneWidget);
  });

  testWidgets('discs and support files get their own labels', (tester) async {
    const multiDisc = GameDetail(
      id: 7,
      title: 'Final Fantasy VII',
      systemCode: 'psx',
      systemName: 'PlayStation',
      hasCover: false,
      totalSize: 30,
      files: [
        GameFileModel(
          id: 1,
          name: 'ff7-d1.cue',
          relativePath: 'psx/ff7-d1.cue',
          role: FileRole.disc,
          discNumber: 1,
          version: '',
          size: 10,
        ),
        GameFileModel(
          id: 2,
          name: 'ff7-d1.bin',
          relativePath: 'psx/ff7-d1.bin',
          role: FileRole.support,
          discNumber: null,
          version: '',
          size: 20,
        ),
      ],
    );
    await tester.pumpWidget(_screen(multiDisc));
    await tester.pumpAndSettle();
    expect(find.text('Płyta 1'), findsOneWidget);
    expect(find.text('Pozostałe'), findsOneWidget);
  });

  testWidgets('installed: pill and ghost delete only', (tester) async {
    await tester.pumpWidget(
      _screen(
        _detail,
        local: const LocalGameState(
          status: InstallStatus.installed,
          updateAvailable: false,
          missing: [],
          presentPaths: ['/roms/switch/hk.nsp', '/roms/switch/upd.nsp'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zainstalowana'), findsOneWidget);
    expect(find.text('Usuń z urządzenia'), findsOneWidget);
    expect(find.textContaining('Pobierz'), findsNothing);
  });

  testWidgets('update available: update button and secondary delete', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        _detail,
        local: const LocalGameState(
          status: InstallStatus.partial,
          updateAvailable: true,
          missing: [],
          presentPaths: ['/roms/switch/hk.nsp'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Jest aktualizacja'), findsOneWidget);
    expect(find.text('Pobierz aktualizację · 2 B'), findsOneWidget);
    expect(find.text('Usuń z urządzenia'), findsOneWidget);
  });

  testWidgets('partial without update shows the partial pill', (tester) async {
    await tester.pumpWidget(
      _screen(
        _detail,
        local: const LocalGameState(
          status: InstallStatus.partial,
          updateAvailable: false,
          missing: [],
          presentPaths: ['/roms/switch/upd.nsp'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Częściowo'), findsOneWidget);
  });

  testWidgets('offline disables download', (tester) async {
    await tester.pumpWidget(
      _screen(_detail, overrides: [isOfflineProvider.overrideWithValue(true)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline — pobieranie niedostępne'), findsOneWidget);
  });

  testWidgets('with a cover the hero renders two images', (tester) async {
    await tester.pumpWidget(
      _screen(
        const GameDetail(
          id: 7,
          title: 'Hollow Knight',
          systemCode: 'switch',
          systemName: 'Switch',
          hasCover: true,
          totalSize: 3,
          files: [],
        ),
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://nas:8000', token: 't'),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(CoverImage), findsNWidgets(2));
  });

  testWidgets('an error shows a retry action', (tester) async {
    await tester.pumpWidget(
      _screen(
        _detail,
        overrides: [
          gameDetailProvider(7)
              .overrideWith((ref) async => throw StateError('x')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
    await tester.tap(find.text('Ponów'));
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
  });

  testWidgets('local state error is humanized', (tester) async {
    await tester.pumpWidget(
      _screen(
        _detail,
        overrides: [
          localStateProvider(7)
              .overrideWith((ref) async => throw StateError('dysk')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('dysk'), findsOneWidget);
  });

  testWidgets('loading skeleton', (tester) async {
    await tester.pumpWidget(
      _screen(
        _detail,
        overrides: [
          gameDetailProvider(7).overrideWith(
            (ref) => Future.delayed(const Duration(days: 1), () => _detail),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(PulseBox), findsWidgets);
  });
}
```

Dodaj importy `package:droplet/core/api/api_client.dart`, `package:droplet/core/session/providers.dart`, `package:droplet/features/library/widgets/cover_image.dart`, `package:droplet/app/widgets/pulse_box.dart`.

W `game_actions_test.dart` zaktualizuj asercje: `find.textContaining('Pobierz')` → `find.text('Pobierz · 1.0 KB')`; `find.text('Pobierz aktualizację')` → `find.textContaining('Pobierz aktualizację')`; helper `build` dodaje override `downloaderPortProvider.overrideWithValue(FakeDownloaderPort())` i `storageSettingsProvider` jak wyżej oraz owija w `MaterialApp.router` z trasą `/game/7` (skopiuj `_router` z pliku wyżej). Testy pobierania (`snackbar` przy braku uprawnień / miejsca) zostają — szukają `textContaining`.

W `download_flow_test.dart` (test widgetowy przepływu): przycisk pobierania znajdź przez `find.textContaining('Pobierz ·')`.

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd app && flutter test test/features/game_detail_test.dart`

- [ ] **Step 3: Provider wolnego miejsca**

Dopisz do `app/lib/features/game/providers.dart`:

```dart
import '../../core/platform/downloader_port.dart';

/// Wolne bajty na wolumenie katalogu ROMów; null = nieznane (pomijamy).
final freeBytesProvider = FutureProvider.family<int?, String>(
  (ref, path) => ref.watch(downloaderPortProvider).freeBytes(path),
);
```

- [ ] **Step 4: Ekran**

```dart
// app/lib/features/game/game_detail_screen.dart
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../app/widgets/circle_icon_button.dart';
import '../../app/widgets/glass_panel.dart';
import '../../app/widgets/pill.dart';
import '../../app/widgets/primary_button.dart';
import '../../app/widgets/pulse_box.dart';
import '../../app/widgets/section_label.dart';
import '../../core/api/models.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/downloads/local_state.dart';
import '../../core/downloads/selection.dart';
import '../../core/downloads/space.dart';
import '../../core/downloads/storage_settings.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/session/providers.dart';
import '../library/providers.dart';
import '../library/widgets/cover_image.dart';
import 'delete_dialog.dart';
import 'providers.dart';

const roleLabels = {
  FileRole.base: 'Gra',
  FileRole.update: 'Aktualizacja',
  FileRole.dlc: 'DLC',
  FileRole.disc: 'Płyta',
  FileRole.support: 'Pozostałe',
  FileRole.other: 'Pozostałe',
};

String labelFor(GameFileModel file) => file.role == FileRole.disc
    ? '${roleLabels[FileRole.disc]} ${file.discNumber ?? ''}'.trim()
    : roleLabels[file.role]!;

/// Ile realnie zejdzie z sieci: zaznaczone pliki, których nie ma na dysku.
int bytesToFetch(GameDetail game, Set<int> selected, LocalGameState local) {
  final present = {for (final p in local.presentPaths) p.split('/').last};
  return game.files
      .where((f) => selected.contains(f.id) && !present.contains(f.name))
      .fold(0, (sum, f) => sum + f.size);
}

const _heroHeight = 260.0;

class GameDetailScreen extends ConsumerWidget {
  const GameDetailScreen({super.key, required this.gameId});

  final int gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(gameDetailProvider(gameId));
    return detail.when(
      loading: () => const Scaffold(body: _DetailSkeleton()),
      error: (error, _) => Scaffold(
        body: _Error(
          message: humanizeError(error),
          onRetry: () => ref.invalidate(gameDetailProvider(gameId)),
        ),
      ),
      data: (game) => _Detail(game: game),
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({required this.game});

  final GameDetail game;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  late final Set<int> _selected = defaultSelection(widget.game.files);

  GameDetail get game => widget.game;

  void _toggle(GameFileModel file, bool? on) => setState(() {
        if (on ?? false) {
          _selected.add(file.id);
        } else {
          _selected.remove(file.id);
        }
      });

  Future<void> _download(LocalGameState local) async {
    final session = (await ref.read(sessionProvider.future))!;
    final settings = await ref.read(storageSettingsProvider.future);
    try {
      await ref.read(downloadManagerProvider).downloadGame(
            game: game,
            selectedIds: _selected,
            local: local,
            serverUrl: session.serverUrl,
            authHeaders: {'Authorization': 'Token ${session.token}'},
            settings: settings,
          );
    } on PermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bez dostępu do plików nie pobiorę ROM-ów — '
            'przyznaj uprawnienie w ustawieniach',
          ),
        ),
      );
    } on InsufficientSpaceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(localStateProvider(game.id));
    final grouped = <String, List<GameFileModel>>{};
    for (final file in game.files) {
      grouped.putIfAbsent(labelFor(file), () => []).add(file);
    }
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Hero(game: game)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            sliver: SliverList.list(
              children: [
                Text(
                  game.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: kText,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Pill(game.systemName),
                    Pill(formatBytes(game.totalSize)),
                    if (local.value case final state?)
                      if (_statePill(state) case final text?)
                        Pill(text, accent: true),
                  ],
                ),
                const SizedBox(height: 8),
                for (final entry in grouped.entries) ...[
                  SectionLabel(
                    entry.key,
                    trailing: entry.key == roleLabels[FileRole.update]
                        ? 'najnowsza domyślnie'
                        : null,
                  ),
                  for (final file in entry.value)
                    _FileRow(
                      file: file,
                      selected: _selected.contains(file.id),
                      onChanged: (on) => _toggle(file, on),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: local.when(
        loading: () => const _BottomBar(
          child: PrimaryButton(label: 'Sprawdzam pliki...', onPressed: null),
        ),
        error: (e, _) => _BottomBar(
          child: Text(
            humanizeError(e),
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextDim),
          ),
        ),
        data: (state) => _BottomBar(
          child: _Actions(
            game: game,
            state: state,
            toFetch: bytesToFetch(game, _selected, state),
            offline: ref.watch(isOfflineProvider),
            onDownload: () => _download(state),
            onDelete: () => confirmAndDelete(context, ref, game.id, state),
          ),
        ),
      ),
    );
  }

  static String? _statePill(LocalGameState state) {
    if (state.updateAvailable) return 'Jest aktualizacja';
    return switch (state.status) {
      InstallStatus.installed => 'Zainstalowana',
      InstallStatus.partial => 'Częściowo',
      InstallStatus.none => null,
    };
  }
}

/// Rozmyta okładka jako tło, ostra na wierzchu, wstecz w rogu.
class _Hero extends ConsumerWidget {
  const _Hero({required this.game});

  final GameDetail game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = game.hasCover ? ref.watch(apiClientProvider) : null;
    final url = client?.coverUrl(game.id, size: 'full') ?? '';
    final headers = client?.authHeaders ?? const <String, String>{};
    return SizedBox(
      height: _heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (game.hasCover)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: CoverImage(
                title: game.title,
                url: url,
                headers: headers,
                hasCover: true,
                fit: BoxFit.cover,
              ),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(gradient: coverPlaceholderGradient),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x80000000), Colors.transparent, kBgMid],
                stops: [0.0, 0.35, 1.0],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Hero(
                tag: 'cover-${game.id}',
                child: Container(
                  height: 150,
                  width: 150 * 3 / 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kRadiusCover),
                    border: Border.all(color: kGlassBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x99000000),
                        blurRadius: 40,
                        offset: Offset(0, 20),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CoverImage(
                    title: game.title,
                    url: url,
                    headers: headers,
                    hasCover: game.hasCover,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            child: CircleIconButton(
              key: const Key('back-button'),
              icon: Icons.arrow_back_rounded,
              tooltip: 'Wstecz',
              onPressed: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.selected,
    required this.onChanged,
  });

  final GameFileModel file;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: selected ? 1 : 0.55,
        child: GlassPanel(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
          onTap: () => onChanged(!selected),
          child: Row(
            children: [
              Checkbox(value: selected, onChanged: onChanged),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kText, fontSize: 14),
                    ),
                    if (file.version.isNotEmpty)
                      Text(
                        file.version,
                        style: const TextStyle(color: kTextDim, fontSize: 11),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatBytes(file.size),
                style: const TextStyle(color: kTextDim, fontSize: 13),
              ),
            ],
          ),
        ),
      );
}

/// Dolny pasek: gradient do tła, żeby lista „wchodziła" pod przycisk.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, kBgBottom],
            stops: [0.0, 0.4],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: child,
          ),
        ),
      );
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.game,
    required this.state,
    required this.toFetch,
    required this.offline,
    required this.onDownload,
    required this.onDelete,
  });

  final GameDetail game;
  final LocalGameState state;
  final int toFetch;
  final bool offline;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(storageSettingsProvider).value;
    final dir = settings?.dirFor(game.systemCode);
    final free = settings == null
        ? null
        : ref.watch(freeBytesProvider(settings.baseDir)).value;
    final installed =
        state.status == InstallStatus.installed && !state.updateAvailable;
    final label = state.updateAvailable
        ? 'Pobierz aktualizację · ${formatBytes(toFetch)}'
        : 'Pobierz · ${formatBytes(toFetch)}';
    final footer = offline
        ? 'Offline — pobieranie niedostępne'
        : [
            if (free != null) 'Wolne ${formatBytes(free)}',
            if (dir != null) 'zapis: $dir',
          ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (installed)
          PrimaryButton(label: 'Usuń z urządzenia', onPressed: onDelete, ghost: true)
        else ...[
          PrimaryButton(label: label, onPressed: offline ? null : onDownload),
          if (state.presentPaths.isNotEmpty)
            TextButton(
              onPressed: onDelete,
              child: const Text(
                'Usuń z urządzenia',
                style: TextStyle(color: kTextDim),
              ),
            ),
        ],
        if (footer.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            footer,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kTextDim, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextDim),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 160,
                child: PrimaryButton(label: 'Ponów', onPressed: onRetry),
              ),
            ],
          ),
        ),
      );
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.zero,
        children: const [
          PulseBox(height: _heroHeight, radius: BorderRadius.zero),
          Padding(
            padding: EdgeInsets.fromLTRB(60, 18, 60, 8),
            child: PulseBox(height: 24),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 110),
            child: PulseBox(height: 22),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 28, 20, 0),
            child: PulseBox(height: 52),
          ),
        ],
      );
}
```

Uwaga do testu z okładką (`hasCover: true`): hero renderuje dwa `CoverImage` — oba `CachedNetworkImage` bez sieci w teście pokazują placeholder; nie wywołuj `pumpAndSettle` (pętla animacji), tylko `pump()`.

Uwaga do testu „hero, pills…”: `MediaQuery.paddingOf` w teście = 0, przycisk wstecz jest na (12, 8).

- [ ] **Step 5: Testy**

Run: `cd app && flutter test test/features/game_detail_test.dart test/features/game_actions_test.dart test/features/download_flow_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/game app/test/features
git commit -m "feat(game): karta gry z rozmytym tłem, pigułkami i przyklejonym przyciskiem"
```

---

### Task 9: Pobierania

**Files:**
- Create: `app/lib/features/downloads/providers.dart`
- Modify: `app/lib/features/downloads/downloads_screen.dart` (przepisanie)
- Modify: `app/lib/features/library/library_screen.dart` (import `activeDownloadsProvider` z nowego pliku — plik i tak znika w Task 12)
- Test: `app/test/features/downloads_screen_test.dart` (zastąp)

**Interfaces:**
- Consumes: `downloadManagerProvider`, `GameProgress` (z bajtami/prędkością), `CoverImage`, `GlassPanel`, `CircleIconButton`, `SectionLabel`, `formatBytes`.
- Produces: `activeDownloadsProvider` (`Provider<List<GameProgress>>`, wszystkie wpisy managera) w `features/downloads/providers.dart`; `activeCountProvider` (`Provider<int>` — liczba wpisów `running`/`paused`); `String progressSubtitle(GameProgress)`; `DownloadsScreen`.
- Teksty: nagłówek `Pobierania`, podtytuł `N aktywnych · pozostało X` lub `Brak aktywnych`; wiersz: running `X / Y · Z/s` (bez prędkości: `X / Y`), paused `Wstrzymane · X / Y`, failed `Błąd pobierania — ponów`, complete `Gotowe · Y`; sekcja `Zakończone` z `Wyczyść`; pusty stan `Brak pobierań` / `Wybierz grę i naciśnij Pobierz.`

- [ ] **Step 1: Testy**

```dart
// app/test/features/downloads_screen_test.dart
import 'package:droplet/core/downloads/download_manager.dart';
import 'package:droplet/features/downloads/downloads_screen.dart';
import 'package:droplet/features/downloads/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_permissions_port.dart';

GoRouter _router() => GoRouter(
      initialLocation: '/downloads',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: 'downloads',
              builder: (_, __) => const DownloadsScreen(),
            ),
            GoRoute(
              path: 'game/:id',
              builder: (_, s) =>
                  Scaffold(body: Text('Gra ${s.pathParameters['id']}')),
            ),
          ],
        ),
      ],
    );

Widget _screen(List<GameProgress> active, DownloadManager manager) =>
    ProviderScope(
      overrides: [
        activeDownloadsProvider.overrideWith((ref) => active),
        downloadManagerProvider.overrideWithValue(manager),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

GameProgress at(
  GameProgressStatus status, {
  int id = 7,
  double progress = 0.5,
  int done = 500,
  int total = 1000,
  int? speed,
}) =>
    GameProgress(
      gameId: id,
      title: 'Mario',
      systemCode: 'snes',
      hasCover: false,
      progress: progress,
      status: status,
      bytesDone: done,
      bytesTotal: total,
      speedBytesPerSec: speed,
    );

void main() {
  late FakeDownloaderPort port;
  late DownloadManager manager;

  setUp(() {
    port = FakeDownloaderPort();
    manager = DownloadManager(
      port,
      FakePermissionsPort(granted: true),
      onGameChanged: (_) {},
    );
  });

  tearDown(() => manager.dispose());

  test('progressSubtitle per status', () {
    expect(progressSubtitle(at(GameProgressStatus.running, speed: 2048)),
        '500 B / 1000 B · 2.0 KB/s');
    expect(progressSubtitle(at(GameProgressStatus.running)), '500 B / 1000 B');
    expect(progressSubtitle(at(GameProgressStatus.paused)),
        'Wstrzymane · 500 B / 1000 B');
    expect(progressSubtitle(at(GameProgressStatus.failed)),
        'Błąd pobierania — ponów');
    expect(progressSubtitle(at(GameProgressStatus.complete)), 'Gotowe · 1000 B');
  });

  testWidgets('empty state', (tester) async {
    await tester.pumpWidget(_screen(const [], manager));
    await tester.pumpAndSettle();
    expect(find.text('Brak pobierań'), findsOneWidget);
    expect(find.text('Brak aktywnych'), findsOneWidget);
  });

  testWidgets('header sums what is left; card opens the game', (tester) async {
    await tester.pumpWidget(
      _screen([at(GameProgressStatus.running), at(GameProgressStatus.paused, id: 8)], manager),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 aktywnych · pozostało 1000 B'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    await tester.tap(find.text('Mario').first);
    await tester.pumpAndSettle();
    expect(find.text('Gra 7'), findsOneWidget);
  });

  testWidgets('pause / cancel / resume / retry reach the manager', (
    tester,
  ) async {
    await tester.pumpWidget(_screen([at(GameProgressStatus.running)], manager));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(manager.progress, isEmpty);

    await tester.pumpWidget(_screen([at(GameProgressStatus.paused)], manager));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_screen([at(GameProgressStatus.failed)], manager));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
  });

  testWidgets('finished section and clear', (tester) async {
    await tester.pumpWidget(
      _screen([at(GameProgressStatus.complete), at(GameProgressStatus.failed, id: 9)], manager),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zakończone'), findsOneWidget);
    expect(find.text('Gotowe · 1000 B'), findsOneWidget);
    await tester.tap(find.text('Wyczyść'));
    await tester.pumpAndSettle();
    // Manager had nothing of its own; the tap must not throw.
    expect(manager.progress, isEmpty);
  });

  test('activeCountProvider counts running and paused', () {
    final container = ProviderContainer(
      overrides: [
        activeDownloadsProvider.overrideWith(
          (ref) => [
            at(GameProgressStatus.running),
            at(GameProgressStatus.paused, id: 8),
            at(GameProgressStatus.complete, id: 9),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(activeCountProvider), 2);
  });
}
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd app && flutter test test/features/downloads_screen_test.dart`

- [ ] **Step 3: Providery**

```dart
// app/lib/features/downloads/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/downloads/download_manager.dart';
import '../../core/format.dart';

final _progressStreamProvider = StreamProvider<Map<int, GameProgress>>(
  (ref) => ref.watch(downloadManagerProvider).progressStream,
);

/// Wszystkie wpisy managera (aktywne i zakończone), w kolejności dodania.
final activeDownloadsProvider = Provider<List<GameProgress>>((ref) {
  final live = ref.watch(_progressStreamProvider).value;
  final current = live ?? ref.watch(downloadManagerProvider).progress;
  return current.values.toList();
});

bool isActive(GameProgress p) =>
    p.status == GameProgressStatus.running ||
    p.status == GameProgressStatus.paused;

final activeCountProvider = Provider<int>(
  (ref) => ref.watch(activeDownloadsProvider).where(isActive).length,
);

String progressSubtitle(GameProgress p) {
  final bytes = '${formatBytes(p.bytesDone)} / ${formatBytes(p.bytesTotal)}';
  return switch (p.status) {
    GameProgressStatus.running => p.speedBytesPerSec == null
        ? bytes
        : '$bytes · ${formatBytes(p.speedBytesPerSec!)}/s',
    GameProgressStatus.paused => 'Wstrzymane · $bytes',
    GameProgressStatus.failed => 'Błąd pobierania — ponów',
    GameProgressStatus.complete => 'Gotowe · ${formatBytes(p.bytesTotal)}',
  };
}
```

Usuń `_progressStreamProvider` i `activeDownloadsProvider` z `downloads_screen.dart`; w `library_screen.dart` zmień import na `../downloads/providers.dart`.

- [ ] **Step 4: Ekran**

```dart
// app/lib/features/downloads/downloads_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../app/widgets/circle_icon_button.dart';
import '../../app/widgets/glass_panel.dart';
import '../../app/widgets/section_label.dart';
import '../../core/api/models.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/format.dart';
import '../library/widgets/game_tile.dart';
import 'providers.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(activeDownloadsProvider);
    final active = all.where(isActive).toList();
    final finished = all.where((p) => !isActive(p)).toList();
    final left = active.fold(0, (sum, p) => sum + p.bytesLeft);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, kListBottomPad),
          children: [
            const Text(
              'Pobierania',
              style: TextStyle(
                color: kText,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
            Text(
              active.isEmpty
                  ? 'Brak aktywnych'
                  : '${active.length} aktywnych · pozostało ${formatBytes(left)}',
              style: const TextStyle(color: kTextDim, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (all.isEmpty) const _Empty(),
            for (final p in active) _DownloadCard(progress: p),
            if (finished.isNotEmpty) ...[
              SectionLabel(
                'Zakończone',
                trailing: 'Wyczyść',
                onTrailingTap: () =>
                    ref.read(downloadManagerProvider).clearFinished(),
              ),
              for (final p in finished) _DownloadCard(progress: p),
            ],
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Icon(Icons.download_rounded, size: 40, color: kTextDim),
            SizedBox(height: 12),
            Text('Brak pobierań', style: TextStyle(color: kText, fontSize: 17)),
            SizedBox(height: 6),
            Text(
              'Wybierz grę i naciśnij Pobierz.',
              style: TextStyle(color: kTextDim),
            ),
          ],
        ),
      );
}

class _DownloadCard extends ConsumerWidget {
  const _DownloadCard({required this.progress});

  final GameProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(downloadManagerProvider);
    final failed = progress.status == GameProgressStatus.failed;
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      onTap: () => context.go('/game/${progress.gameId}'),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: CoverThumb(
              game: GameSummary(
                id: progress.gameId,
                title: progress.title,
                systemCode: progress.systemCode,
                hasCover: progress.hasCover,
                totalSize: progress.bytesTotal,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  progress.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  progressSubtitle(progress),
                  style: TextStyle(
                    color: failed ? kDanger : kTextDim,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.progress,
                    minHeight: 5,
                    backgroundColor: kGlass,
                    color: failed ? kDanger : kAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ..._actions(manager),
        ],
      ),
    );
  }

  List<Widget> _actions(DownloadManager manager) => switch (progress.status) {
        GameProgressStatus.running => [
            CircleIconButton(
              icon: Icons.pause_rounded,
              tooltip: 'Wstrzymaj',
              onPressed: () => manager.pauseGame(progress.gameId),
            ),
            const SizedBox(width: 6),
            CircleIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Anuluj',
              onPressed: () => manager.cancelGame(progress.gameId),
            ),
          ],
        GameProgressStatus.paused => [
            CircleIconButton(
              icon: Icons.play_arrow_rounded,
              tooltip: 'Wznów',
              onPressed: () => manager.resumeGame(progress.gameId),
            ),
            const SizedBox(width: 6),
            CircleIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Anuluj',
              onPressed: () => manager.cancelGame(progress.gameId),
            ),
          ],
        GameProgressStatus.failed => [
            CircleIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Ponów',
              onPressed: () => manager.retryGame(progress.gameId),
            ),
          ],
        GameProgressStatus.complete => const [
            Icon(Icons.check_circle_rounded, color: kAccent),
          ],
      };
}
```

`CoverThumb` w karcie pobierania z `hasCover: false` nie tworzy klienta; z okładką bierze `apiClientProvider` — w testach `hasCover: false`.

- [ ] **Step 5: Testy**

Run: `cd app && flutter test test/features/downloads_screen_test.dart test/features/library_screen_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/downloads app/lib/features/library/library_screen.dart app/test/features/downloads_screen_test.dart
git commit -m "feat(downloads): karty z okładką, prędkością i sekcją zakończonych"
```

---

### Task 10: Ustawienia i foldery per system

**Files:**
- Modify: `app/lib/features/settings/settings_screen.dart` (przepisanie)
- Create: `app/lib/features/settings/folders_screen.dart`
- Test: `app/test/features/settings_test.dart` (zastąp), `app/test/features/settings_downloads_test.dart` (zastąp), `app/test/features/folders_screen_test.dart`

**Interfaces:**
- Consumes: `sessionProvider`, `librarySnapshotProvider`, `isOfflineProvider`, `storageSettingsProvider`, `storageSettingsRepositoryProvider`, `permissionsPortProvider`, `needsAllFilesAccess`, `ensureStoragePermission`, `freeBytesProvider`, `systemsProvider`, `GlassPanel`, `SectionLabel`, `CircleIconButton`, `PrimaryButton`.
- Produces: `SettingsScreen`, `FoldersScreen`, `const appVersion = '0.2.0'`; `SettingsRow({required String title, String? subtitle, Widget? leading, Widget? trailing, VoidCallback? onTap, Key? key})`.
- Teksty: `Ustawienia`; karta Serwer: `Połączono` / `Offline`, `N gier · M systemów`, `Wyloguj`; karta Pobieranie: `Katalog ROMów` + `Zmień` (dialog `Katalog ROMów` z polem `base-dir-field`, `Anuluj`, `Zapisz`), `Dostęp do plików` (`Przyznany` / `Brak` + `Przyznaj`), `Foldery per system` (podtytuł: kody rozdzielone przecinkami lub `domyślne`), `Pobieraj tylko po Wi‑Fi` (Switch `wifi-only`); karta Urządzenie: `Wolne miejsce` (`—` gdy nieznane); karta O aplikacji: `Droplet 0.2.0`, `API v1`.

- [ ] **Step 1: Testy**

`app/test/features/settings_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/core/platform/permissions_port.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_permissions_port.dart';

const systems = [
  SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 2),
  SystemModel(id: 2, code: 'psx', name: 'PSX', gameCount: 1),
];

GoRouter _router() => GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (_, __) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'folders',
                  builder: (_, __) => const Scaffold(body: Text('Foldery')),
                ),
              ],
            ),
          ],
        ),
      ],
    );

Widget _screen({
  required SessionRepository repo,
  PermissionsPort? port,
  FakeDownloaderPort? downloader,
  bool offline = false,
}) =>
    ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        permissionsPortProvider
            .overrideWithValue(port ?? FakePermissionsPort(granted: true)),
        downloaderPortProvider
            .overrideWithValue(downloader ?? FakeDownloaderPort()),
        librarySnapshotProvider.overrideWith(
          (ref) async => LibrarySnapshot(
            systems: systems,
            games: [
              for (var i = 1; i <= 3; i++)
                GameSummary(
                  id: i,
                  title: 'G$i',
                  systemCode: 'snes',
                  hasCover: false,
                  totalSize: 1,
                ),
            ],
            fromCache: offline,
            previousIds: const {},
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

Future<SessionRepository> _signedIn() async {
  final repo = SessionRepository(MemoryKeyValueStore());
  await repo.save(const Session(serverUrl: 'http://nas:8000', token: 't'));
  return repo;
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('server card: status, counts, sign out', (tester) async {
    final repo = await _signedIn();
    await tester.pumpWidget(_screen(repo: repo));
    await tester.pumpAndSettle();
    expect(find.text('Ustawienia'), findsOneWidget);
    expect(find.text('Połączono'), findsOneWidget);
    expect(find.text('http://nas:8000 · 3 gier · 2 systemów'), findsOneWidget);
    expect(find.text('Droplet $appVersion'), findsOneWidget);
    expect(find.text('API v1'), findsOneWidget);
    await tester.tap(find.text('Wyloguj'));
    await tester.pumpAndSettle();
    expect(await repo.load(), isNull);
  });

  testWidgets('offline status and unknown free space', (tester) async {
    await tester.pumpWidget(_screen(repo: await _signedIn(), offline: true));
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('free space is shown when known', (tester) async {
    final downloader = FakeDownloaderPort()..free = 2048;
    await tester.pumpWidget(
      _screen(repo: await _signedIn(), downloader: downloader),
    );
    await tester.pumpAndSettle();
    expect(find.text('2.0 KB'), findsOneWidget);
  });

  testWidgets('no session shows placeholder', (tester) async {
    await tester.pumpWidget(
      _screen(repo: SessionRepository(MemoryKeyValueStore())),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Nie zalogowano'), findsOneWidget);
  });

  testWidgets('folders row opens the sub-screen', (tester) async {
    await tester.pumpWidget(_screen(repo: await _signedIn()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Foldery per system'), 200);
    await tester.tap(find.text('Foldery per system'));
    await tester.pumpAndSettle();
    expect(find.text('Foldery'), findsOneWidget);
  });
}
```

`app/test/features/settings_downloads_test.dart`:

```dart
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/core/platform/permissions_port.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_permissions_port.dart';

Widget _screen({
  required StorageSettingsRepository repo,
  required PermissionsPort port,
}) =>
    ProviderScope(
      overrides: [
        sessionRepositoryProvider
            .overrideWithValue(SessionRepository(MemoryKeyValueStore())),
        storageSettingsRepositoryProvider.overrideWithValue(repo),
        permissionsPortProvider.overrideWithValue(port),
        downloaderPortProvider.overrideWithValue(FakeDownloaderPort()),
        librarySnapshotProvider.overrideWith(
          (ref) async => const LibrarySnapshot(
            systems: [],
            games: [],
            fromCache: false,
            previousIds: {},
          ),
        ),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('base dir is edited through a dialog', (tester) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await tester.pumpWidget(
      _screen(repo: repo, port: FakePermissionsPort(granted: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text(defaultBaseDir), findsOneWidget);
    expect(find.text('Przyznany'), findsOneWidget);
    await tester.tap(find.text('Zmień'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('base-dir-field')), '/tmp/roms');
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect((await repo.load()).baseDir, '/tmp/roms');
    expect(find.text('/tmp/roms'), findsOneWidget);
  });

  testWidgets('cancel leaves the dir alone', (tester) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await tester.pumpWidget(
      _screen(repo: repo, port: FakePermissionsPort(granted: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zmień'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('base-dir-field')), '/nope');
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect((await repo.load()).baseDir, defaultBaseDir);
  });

  testWidgets('grant button requests permission', (tester) async {
    final port = FakePermissionsPort(granted: false, grantOnRequest: true);
    await tester.pumpWidget(
      _screen(repo: StorageSettingsRepository(SharedPreferencesAsync()), port: port),
    );
    await tester.pumpAndSettle();
    expect(find.text('Brak'), findsOneWidget);
    await tester.tap(find.byKey(const Key('grant-permission')));
    await tester.pumpAndSettle();
    expect(port.requests, 1);
    expect(find.text('Przyznany'), findsOneWidget);
  });

  testWidgets('wifi-only switch persists', (tester) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await tester.pumpWidget(
      _screen(repo: repo, port: FakePermissionsPort(granted: true)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('wifi-only')), 200);
    await tester.tap(find.byKey(const Key('wifi-only')));
    await tester.pumpAndSettle();
    expect((await repo.load()).wifiOnly, isTrue);
  });

  testWidgets('settings load error is shown', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider
              .overrideWithValue(SessionRepository(MemoryKeyValueStore())),
          storageSettingsProvider
              .overrideWith((ref) async => throw StateError('prefs')),
          permissionsPortProvider
              .overrideWithValue(FakePermissionsPort(granted: true)),
          downloaderPortProvider.overrideWithValue(FakeDownloaderPort()),
          librarySnapshotProvider.overrideWith(
            (ref) async => const LibrarySnapshot(
              systems: [],
              games: [],
              fromCache: false,
              previousIds: {},
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('prefs'), findsOneWidget);
  });
}
```

`app/test/features/folders_screen_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/settings/folders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const systems = [
  SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 1),
];

GoRouter _router() => GoRouter(
      initialLocation: '/settings/folders',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('Ustawienia')),
          routes: [
            GoRoute(
              path: 'folders',
              builder: (_, __) => const FoldersScreen(),
            ),
          ],
        ),
      ],
    );

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('edits per-system dirs and goes back', (tester) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageSettingsRepositoryProvider.overrideWithValue(repo),
          systemsProvider.overrideWith((ref) async => systems),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Foldery per system'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('system-dir-snes')), 'SNES');
    await tester.pumpAndSettle();
    expect((await repo.load()).systemDirs['snes'], 'SNES');
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Ustawienia'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd app && flutter test test/features/settings_test.dart test/features/settings_downloads_test.dart test/features/folders_screen_test.dart`

- [ ] **Step 3: SettingsScreen**

```dart
// app/lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../app/widgets/glass_panel.dart';
import '../../app/widgets/section_label.dart';
import '../../core/downloads/permissions.dart';
import '../../core/downloads/storage_settings.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/session/providers.dart';
import '../game/providers.dart';
import '../library/providers.dart';

const appVersion = '0.2.0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, kListBottomPad),
            children: const [
              Text(
                'Ustawienia',
                style: TextStyle(
                  color: kText,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              SizedBox(height: 12),
              _ServerCard(),
              SectionLabel('Pobieranie'),
              _DownloadCard(),
              SectionLabel('Urządzenie'),
              _DeviceCard(),
              SectionLabel('O aplikacji'),
              GlassPanel(
                padding: EdgeInsets.zero,
                child: SettingsRow(
                  title: 'Droplet $appVersion',
                  trailing: Text('API v1', style: TextStyle(color: kTextDim)),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Jeden wiersz karty ustawień.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: kText, fontSize: 14),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(color: kTextDim, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 14, endIndent: 14);
}

class _ServerCard extends ConsumerWidget {
  const _ServerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final offline = ref.watch(isOfflineProvider);
    final snapshot = ref.watch(librarySnapshotProvider).value;
    final counts = snapshot == null
        ? ''
        : ' · ${snapshot.games.length} gier · ${snapshot.systems.length} systemów';
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingsRow(
            leading: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: offline ? kTextDim : kOk,
                shape: BoxShape.circle,
                boxShadow: offline
                    ? null
                    : [BoxShadow(color: kOk.withValues(alpha: 0.7), blurRadius: 10)],
              ),
            ),
            title: offline ? 'Offline' : 'Połączono',
            subtitle: session == null
                ? 'Nie zalogowano'
                : '${session.serverUrl}$counts',
          ),
          const _Divider(),
          SettingsRow(
            title: 'Wyloguj',
            trailing: const Icon(Icons.logout, size: 18, color: kTextDim),
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class _DownloadCard extends ConsumerWidget {
  const _DownloadCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(storageSettingsProvider);
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: settings.when(
        loading: () => const SettingsRow(title: '...'),
        error: (e, _) => SettingsRow(title: humanizeError(e)),
        data: (data) => Column(
          children: [
            SettingsRow(
              title: 'Katalog ROMów',
              subtitle: data.baseDir,
              trailing: TextButton(
                onPressed: () => _editBaseDir(context, ref, data.baseDir),
                child: const Text('Zmień'),
              ),
            ),
            const _Divider(),
            _PermissionRow(baseDir: data.baseDir),
            const _Divider(),
            SettingsRow(
              title: 'Foldery per system',
              subtitle: data.systemDirs.isEmpty
                  ? 'domyślne'
                  : data.systemDirs.keys.join(', '),
              trailing: const Icon(Icons.chevron_right, color: kTextDim),
              onTap: () => context.go('/settings/folders'),
            ),
            const _Divider(),
            SettingsRow(
              title: 'Pobieraj tylko po Wi‑Fi',
              trailing: Switch(
                key: const Key('wifi-only'),
                value: data.wifiOnly,
                onChanged: (v) async {
                  await ref
                      .read(storageSettingsRepositoryProvider)
                      .saveWifiOnly(v);
                  ref.invalidate(storageSettingsProvider);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editBaseDir(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Katalog ROMów'),
        content: TextField(
          key: const Key('base-dir-field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            helperText: 'Katalog RetroArch na telefonie',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    await ref.read(storageSettingsRepositoryProvider).saveBaseDir(value);
    ref.invalidate(storageSettingsProvider);
  }
}

class _PermissionRow extends ConsumerStatefulWidget {
  const _PermissionRow({required this.baseDir});

  final String baseDir;

  @override
  ConsumerState<_PermissionRow> createState() => _PermissionRowState();
}

class _PermissionRowState extends ConsumerState<_PermissionRow> {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _PermissionRow old) {
    super.didUpdateWidget(old);
    if (old.baseDir != widget.baseDir) _refresh();
  }

  Future<void> _refresh() async {
    final port = ref.read(permissionsPortProvider);
    final needed = needsAllFilesAccess(widget.baseDir, await port.appPrivateDirs());
    final granted = !needed || await port.hasAllFilesAccess();
    if (mounted) setState(() => _granted = granted);
  }

  Future<void> _grant() async {
    await ensureStoragePermission(ref.read(permissionsPortProvider), widget.baseDir);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => SettingsRow(
        title: 'Dostęp do plików',
        subtitle: _granted == true ? 'Przyznany' : 'Brak',
        trailing: _granted == true
            ? const Icon(Icons.check_rounded, color: kAccent, size: 18)
            : TextButton(
                key: const Key('grant-permission'),
                onPressed: _grant,
                child: const Text('Przyznaj'),
              ),
      );
}

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseDir = ref.watch(storageSettingsProvider).value?.baseDir;
    final free = baseDir == null ? null : ref.watch(freeBytesProvider(baseDir)).value;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: SettingsRow(
        title: 'Wolne miejsce',
        trailing: Text(
          free == null ? '—' : formatBytes(free),
          style: const TextStyle(color: kTextDim),
        ),
      ),
    );
  }
}
```

Import `permissionsPortProvider` z `../../core/platform/permissions_port.dart`.

- [ ] **Step 4: FoldersScreen**

```dart
// app/lib/features/settings/folders_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../app/widgets/circle_icon_button.dart';
import '../../core/downloads/storage_settings.dart';
import '../library/providers.dart';

/// Podkatalog per system w katalogu ROMów (domyślnie kod systemu).
class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systems = ref.watch(systemsProvider).value ?? const [];
    final settings = ref.watch(storageSettingsProvider).value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, kListBottomPad),
          children: [
            Row(
              children: [
                CircleIconButton(
                  key: const Key('back-button'),
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Wstecz',
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Foldery per system',
                  style: TextStyle(
                    color: kText,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Puste pole = podkatalog o nazwie kodu systemu.',
              style: TextStyle(color: kTextDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final system in systems)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextFormField(
                  key: Key('system-dir-${system.code}'),
                  initialValue: settings?.systemDirs[system.code] ?? '',
                  style: const TextStyle(color: kText),
                  decoration: InputDecoration(
                    labelText: system.name,
                    hintText: system.code,
                  ),
                  onChanged: (value) => ref
                      .read(storageSettingsRepositoryProvider)
                      .saveSystemDir(system.code, value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Testy**

Run: `cd app && flutter test test/features/settings_test.dart test/features/settings_downloads_test.dart test/features/folders_screen_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/settings app/test/features
git commit -m "feat(settings): karty ustawień, dialog katalogu, Wi-Fi only, foldery per system"
```

---

### Task 11: Logowanie

**Files:**
- Modify: `app/lib/features/auth/login_screen.dart`
- Test: `app/test/features/login_screen_test.dart` (dopasuj)

**Interfaces:**
- Consumes: `sessionProvider`, `apiClientFactoryProvider` (testy), `GlassPanel`, `PrimaryButton`, `humanizeError`.
- Produces: `LoginScreen` — trzy `TextFormField` w tej kolejności: serwer, login, hasło (e2e wpisuje po indeksach); przycisk `Zaloguj`; błąd pod przyciskiem; stopka `Hasło zostaje na telefonie, appka trzyma tylko token.`

- [ ] **Step 1: Test**

W `login_screen_test.dart` dopisz:

```dart
  testWidgets('glass card and footer are present', (tester) async {
    await tester.pumpWidget(build()); // istniejący helper z fake factory
    expect(find.byType(GlassPanel), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(
      find.text('Hasło zostaje na telefonie, appka trzyma tylko token.'),
      findsOneWidget,
    );
  });
```

(import `package:droplet/app/widgets/glass_panel.dart`). Istniejące testy (walidacja `Wymagane`, błąd `Błędny login lub hasło`, sukces) zostają — sprawdź, że `find.text('Zaloguj')` nadal trafia w przycisk (PrimaryButton renderuje `Text`).

- [ ] **Step 2: Uruchom — FAIL na nowym teście**

- [ ] **Step 3: Implementacja `build` w `_LoginScreenState`** (logika `_submit`, `_messageFor`, kontrolery bez zmian):

```dart
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: kPrimaryGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: kAccent.withValues(alpha: 0.45),
                            blurRadius: 40,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.water_drop_rounded,
                          color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Droplet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kText,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Twoja biblioteka ROMów',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextDim),
                  ),
                  const SizedBox(height: 28),
                  GlassPanel(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _server,
                            decoration: const InputDecoration(
                              labelText: 'Adres serwera',
                              hintText: 'http://192.168.1.10:8000',
                            ),
                            keyboardType: TextInputType.url,
                            validator: _required,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _username,
                            decoration: const InputDecoration(labelText: 'Login'),
                            validator: _required,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            decoration: const InputDecoration(labelText: 'Hasło'),
                            obscureText: true,
                            validator: _required,
                          ),
                          const SizedBox(height: 18),
                          PrimaryButton(
                            label: 'Zaloguj',
                            busy: _busy,
                            onPressed: _busy ? null : _submit,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: kDanger),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Hasło zostaje na telefonie, appka trzyma tylko token.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextDim, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
```

Importy: `../../app/tokens.dart`, `../../app/widgets/glass_panel.dart`, `../../app/widgets/primary_button.dart` (zamiast `../../app/theme.dart`).

- [ ] **Step 4: Testy**

Run: `cd app && flutter test test/features/login_screen_test.dart && flutter analyze`

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/auth app/test/features/login_screen_test.dart
git commit -m "feat(auth): ekran logowania w szklanej karcie"
```

---

### Task 12: Powłoka nawigacyjna, GlassBar, router, sprzątanie starego ekranu

**Files:**
- Create: `app/lib/app/widgets/glass_bar.dart`, `app/lib/app/shell.dart`
- Modify: `app/lib/app/router.dart`, `app/lib/main.dart`, `app/lib/app/theme.dart` (usuń aliasy `kBg`, `kSurface`)
- Delete: `app/lib/features/library/library_screen.dart`, `app/lib/features/library/widgets/game_card.dart`, `app/test/features/library_screen_test.dart`
- Modify: `app/lib/features/library/providers.dart` (usuń `SelectedSystem`, `selectedSystemProvider`, `InstalledOnly`, `installedOnlyProvider`)
- Test: `app/test/app/glass_bar_test.dart`, `app/test/app/router_test.dart` (zastąp)

**Interfaces:**
- Consumes: `HomeScreen`, `SystemScreen`, `GameDetailScreen`, `DownloadsScreen`, `SettingsScreen`, `FoldersScreen`, `LoginScreen`, `activeCountProvider`, `AppBackground`, `buildTheme`, `sessionProvider`.
- Produces:
  - `GlassBar({required int currentIndex, required ValueChanged<int> onTap, int badge = 0})` — trzy pozycje z kluczami `nav-library`, `nav-downloads`, `nav-settings`; odznaka na Pobieraniach gdy `badge > 0`.
  - `AppShell({required StatefulNavigationShell shell, required bool hideBar})`.
  - `routerProvider` z `StatefulShellRoute.indexedStack`; `bool hidesNavBar(String path)` = `path.contains('/game/')`.

- [ ] **Step 1: Testy GlassBar**

```dart
// app/test/app/glass_bar_test.dart
import 'package:droplet/app/widgets/glass_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(find.text('Biblioteka'), findsOneWidget);
    expect(find.text('Pobierania'), findsOneWidget);
    expect(find.text('Ustawienia'), findsOneWidget);
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
}
```

- [ ] **Step 2: Testy routera**

```dart
// app/test/app/router_test.dart
import 'package:droplet/app/router.dart';
import 'package:droplet/app/widgets/glass_bar.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/core/platform/permissions_port.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/auth/login_screen.dart';
import 'package:droplet/features/downloads/downloads_screen.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/home/home_screen.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/settings/settings_screen.dart';
import 'package:droplet/features/system/system_screen.dart';
import 'package:droplet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_permissions_port.dart';

const _detail = GameDetail(
  id: 7,
  title: 'Hollow Knight',
  systemCode: 'switch',
  systemName: 'Switch',
  hasCover: false,
  totalSize: 1,
  files: [],
);

const _games = [
  GameSummary(
    id: 7,
    title: 'Hollow Knight',
    systemCode: 'switch',
    hasCover: false,
    totalSize: 1,
  ),
];
const _systems = [
  SystemModel(id: 1, code: 'switch', name: 'Switch', gameCount: 1),
];

Widget _app(KeyValueStore store) => ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(SessionRepository(store)),
        librarySnapshotProvider.overrideWith(
          (ref) async => const LibrarySnapshot(
            systems: _systems,
            games: _games,
            fromCache: false,
            previousIds: {7},
          ),
        ),
        gameDetailProvider(7).overrideWith((ref) async => _detail),
        localStateProvider(7).overrideWith(
          (ref) async => const LocalGameState(
            status: InstallStatus.none,
            updateAvailable: false,
            missing: [],
            presentPaths: [],
          ),
        ),
        downloaderPortProvider.overrideWithValue(FakeDownloaderPort()),
        permissionsPortProvider.overrideWithValue(
          FakePermissionsPort(granted: true),
        ),
      ],
      child: const DropletApp(),
    );

Future<MemoryKeyValueStore> _signedIn() async {
  final store = MemoryKeyValueStore();
  await SessionRepository(store)
      .save(const Session(serverUrl: 'http://nas:8000', token: 't'));
  return store;
}

void main() {
  test('hidesNavBar only on the game screen', () {
    expect(hidesNavBar('/game/7'), isTrue);
    expect(hidesNavBar('/system/snes'), isFalse);
    expect(hidesNavBar('/downloads'), isFalse);
  });

  testWidgets('no session -> login screen', (tester) async {
    await tester.pumpWidget(_app(MemoryKeyValueStore()));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(GlassBar), findsNothing);
  });

  testWidgets('session -> home with the bar', (tester) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(GlassBar), findsOneWidget);
  });

  testWidgets('library branch keeps its stack; bar hides on the game', (
    tester,
  ) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HomeScreen));

    context.go('/system/switch');
    await tester.pumpAndSettle();
    expect(find.byType(SystemScreen), findsOneWidget);

    context.go('/system/switch/game/7');
    await tester.pumpAndSettle();
    expect(find.byType(GameDetailScreen), findsOneWidget);
    expect(find.byType(GlassBar), findsNothing);

    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.byType(SystemScreen), findsOneWidget);
    expect(find.byType(GlassBar), findsOneWidget);
  });

  testWidgets('bottom tabs switch branches', (tester) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-downloads')));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-library')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('go to a game from downloads lands in the library branch', (
    tester,
  ) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-downloads')));
    await tester.pumpAndSettle();
    tester.element(find.byType(DownloadsScreen)).go('/game/7');
    await tester.pumpAndSettle();
    expect(find.byType(GameDetailScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('signing in redirects away from login', (tester) async {
    final store = MemoryKeyValueStore();
    final repo = SessionRepository(store);
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          librarySnapshotProvider.overrideWith(
            (ref) async => const LibrarySnapshot(
              systems: [],
              games: [],
              fromCache: false,
              previousIds: {},
            ),
          ),
          downloaderPortProvider.overrideWithValue(FakeDownloaderPort()),
          permissionsPortProvider.overrideWithValue(
            FakePermissionsPort(granted: true),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const DropletApp();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await repo.save(const Session(serverUrl: 'http://nas:8000', token: 't'));
    container.read(sessionProvider.notifier).state =
        const AsyncData(Session(serverUrl: 'http://nas:8000', token: 't'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
```

Uwaga: `game/:id` musi być osiągalne zarówno jako `/game/7`, jak i `/system/switch/game/7` — druga trasa zagnieżdżona pod `system/:code`, żeby stos był `[/, /system/switch, /system/switch/game/7]`. `GameTile`/`ShelfCard` robią `context.go('/game/{id}')` z Home (stos `[/, /game/7]`); w `SystemScreen` grid dostaje ścieżkę względną — `GamesGrid` przyjmuje opcjonalny `String Function(int id) routeFor` (domyślnie `'/game/$id'`), a `SystemScreen` przekazuje `(id) => '/system/${widget.code}/game/$id'`. Dodaj ten parametr do `GamesGrid` i `GameTile` (`GameTile({required game, bool hero = true, String? route})`).

- [ ] **Step 3: Uruchom — FAIL**

Run: `cd app && flutter test test/app/glass_bar_test.dart test/app/router_test.dart`

- [ ] **Step 4: GlassBar**

```dart
// app/lib/app/widgets/glass_bar.dart
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Pływająca dolna nawigacja — jedyne miejsce z BackdropFilter poza hero.
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.badge = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int badge;

  static const items = [
    (key: 'nav-library', icon: Icons.grid_view_rounded, label: 'Biblioteka'),
    (key: 'nav-downloads', icon: Icons.download_rounded, label: 'Pobierania'),
    (key: 'nav-settings', icon: Icons.settings_rounded, label: 'Ustawienia'),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kRadiusBar),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: kNavHeight,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(kRadiusBar),
                  border: Border.all(color: kGlassBorder),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _Tab(
                          key: Key(items[i].key),
                          icon: items[i].icon,
                          label: items[i].label,
                          selected: i == currentIndex,
                          badge: i == 1 ? badge : 0,
                          onTap: () => onTap(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? kAccent : kTextDim;
    Widget iconWidget = Icon(icon, size: 22, color: color);
    if (badge > 0) {
      iconWidget = Badge(
        label: Text('$badge'),
        backgroundColor: kAccent,
        textColor: kBgBottom,
        child: iconWidget,
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kRadiusBar),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          iconWidget,
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: AppShell i router**

```dart
// app/lib/app/shell.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/downloads/providers.dart';
import 'theme.dart';
import 'widgets/glass_bar.dart';

bool hidesNavBar(String path) => path.contains('/game/');

/// Tło, jasny pasek statusu i dolna nawigacja dla trzech gałęzi.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell, required this.hideBar});

  final StatefulNavigationShell shell;
  final bool hideBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: AppBackground(
          child: Scaffold(
            extendBody: true,
            body: shell,
            bottomNavigationBar: hideBar
                ? null
                : GlassBar(
                    currentIndex: shell.currentIndex,
                    badge: ref.watch(activeCountProvider),
                    onTap: (i) => shell.goBranch(
                      i,
                      initialLocation: i == shell.currentIndex,
                    ),
                  ),
          ),
        ),
      );
}
```

```dart
// app/lib/app/router.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session/providers.dart';
import '../features/auth/login_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/game/game_detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/settings/folders_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/system/system_screen.dart';
import 'shell.dart';
import 'theme.dart';

GoRoute _gameRoute() => GoRoute(
      path: 'game/:id',
      builder: (_, s) =>
          GameDetailScreen(gameId: int.parse(s.pathParameters['id']!)),
    );

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(sessionProvider).value != null;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const AppBackground(child: LoginScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            AppShell(shell: shell, hideBar: hidesNavBar(state.uri.path)),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, __) => const HomeScreen(),
                routes: [
                  _gameRoute(),
                  GoRoute(
                    path: 'system/:code',
                    builder: (_, s) =>
                        SystemScreen(code: s.pathParameters['code']!),
                    routes: [_gameRoute()],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/downloads',
                builder: (_, __) => const DownloadsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'folders',
                    builder: (_, __) => const FoldersScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
```

`main.dart`: w gałęzi ładowania sesji `home: const AppBackground(child: Scaffold())`; import `app/theme.dart` już jest.

- [ ] **Step 6: Sprzątanie**

- Usuń `library_screen.dart`, `game_card.dart`, `test/features/library_screen_test.dart`.
- Z `providers.dart` usuń `SelectedSystem`, `selectedSystemProvider`, `InstalledOnly`, `installedOnlyProvider`.
- Z `theme.dart` usuń aliasy `kBg`, `kSurface`; `grep -rn "kBg\b\|kSurface" app/lib app/test` ma zwrócić 0 trafień (popraw `delete_dialog.dart` na `kDialogBg`, `pulse_box.dart` już używa `kGlass`).
- `grep -rn "LibraryScreen\|GameCard\|selectedSystemProvider\|installedOnlyProvider\|sortAndFilter" app/` → 0 trafień.

- [ ] **Step 7: Testy i bramka**

Run: `cd app && flutter analyze && cd .. && ./scripts/check_coverage_app.sh`
Expected: PASS, `coverage: … = 100.00%`. Jeśli linia w `MISSING` dotyczy nowego kodu — dopisz test, nie wyłączenie.

- [ ] **Step 8: Commit**

```bash
git add -A app
git commit -m "feat(app): powłoka z dolną nawigacją Glass, StatefulShellRoute, usunięcie starego ekranu biblioteki"
```

---

### Task 13: E2E, wersja, dokumentacja

**Files:**
- Modify: `app/integration_test/app_flow_test.dart`, `app/integration_test/download_flow_test.dart`
- Modify: `app/pubspec.yaml` (`version: 0.2.0+2`)
- Modify: `RALPH-STATUS.md` (sekcja „Czeka na Jana": akceptacja wizualna redesignu na urządzeniu)
- Modify: `docs/superpowers/plans/2026-09-01-droplet-milestones.md` (jedna linia w M6: „UI wg specu redesignu 2026-09-02")

- [ ] **Step 1: `app_flow_test.dart` — nowa nawigacja**

Zamień część testu od `expect(find.text('Super Mario World'), findsWidgets);`:

```dart
    expect(find.text('Super Mario World'), findsWidgets);

    // Nagłówek półki systemu prowadzi do widoku systemu.
    await tester.scrollUntilVisible(find.text('Nintendo Switch'), 200);
    await tester.tap(find.text('Nintendo Switch'));
    await tester.pumpAndSettle();
    expect(find.text('Hollow Knight'), findsWidgets);
    expect(find.text('Super Mario World'), findsNothing);

    await tester.tap(find.text('Hollow Knight').first);
    await tester.pumpAndSettle();
    expect(find.text('Aktualizacja'), findsOneWidget);

    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Hollow Knight'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wyloguj'));
    await tester.pumpAndSettle();
    expect(find.text('Zaloguj'), findsOneWidget);
```

- [ ] **Step 2: `download_flow_test.dart` — katalog przez dialog, gra z półki**

Zamień fragment od komentarza o `MANAGE_EXTERNAL_STORAGE` do końca testu:

```dart
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zmień'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('base-dir-field')), baseDir);
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-library')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Super Mario World').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pobierz ·'));
    await tester.pumpAndSettle();

    var installed = false;
    for (var i = 0; i < 60 && !installed; i++) {
      await tester.pump(const Duration(seconds: 1));
      installed = tester.any(find.text('Zainstalowana'));
    }
    expect(installed, isTrue, reason: 'pobieranie nie zakończyło się w 60 s');

    await tester.tap(find.text('Usuń z urządzenia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pobierz ·'), findsOneWidget);
```

(Zachowaj istniejący komentarz wyjaśniający katalog prywatny i `E2E=true`.)

- [ ] **Step 3: Kompilacja testów integracyjnych bez urządzenia**

Run: `cd app && flutter analyze && flutter build apk --debug --dart-define=E2E=true`
Expected: `flutter analyze` czysto, APK się buduje. Jeżeli `adb devices` pokazuje urządzenie, uruchom dodatkowo `E2E_SERVER=http://<ip-hosta>:8800 ./scripts/e2e_app.sh` (wymaga Dockera); bez urządzenia zapisz to w `RALPH-STATUS.md` jako krok dla Jana — nie udawaj wyniku.

- [ ] **Step 4: Wersja i dokumentacja**

- `app/pubspec.yaml`: `version: 0.2.0+2`.
- `RALPH-STATUS.md`, sekcja „Czeka na Jana", nowy punkt: „**Redesign Glass — akceptacja na urządzeniu.** `cd app && flutter build apk --debug`, wgraj, sprawdź: pasek statusu czytelny na jasnej okładce (Pokémon Crystal), wstecz widoczny na karcie gry i w widoku systemu, dolna nawigacja nie zasłania ostatniego wiersza list, pull‑to‑refresh na ekranie głównym, e2e: `E2E_SERVER=http://<ip>:8800 ./scripts/e2e_app.sh`."
- `docs/superpowers/plans/2026-09-01-droplet-milestones.md`: w opisie M6 dopisz linię „UI: redesign Glass wg `docs/superpowers/specs/2026-09-02-redesign-glass-design.md` (plan `2026-09-02-redesign-glass.md`)".

- [ ] **Step 5: Pełna bramka**

Run: `./scripts/check_coverage_app.sh && cd app && flutter analyze`
Expected: `100.00%`, czysto.

- [ ] **Step 6: Commit**

```bash
git add app/integration_test app/pubspec.yaml RALPH-STATUS.md docs/superpowers/plans/2026-09-01-droplet-milestones.md
git commit -m "test(e2e): przepływy pod nową nawigację; wersja 0.2.0"
```

---

## Samokontrola planu względem specu

| Wymaganie specu | Task |
|---|---|
| Tokeny, `AppBackground`, pasek statusu light | 1, 12 |
| `GlassPanel`, `GlassBar`, `PrimaryButton`, `CircleIconButton`, `Pill`, `SectionLabel`, `PulseBox` | 2, 12, 1 |
| `StatefulShellRoute`, stosy gałęzi, pasek ukryty na `/game/`, klucze nawigacji | 12 |
| Ekran główny: szukajka, offline, półki (recent / installed / systemy, 12 + „Wszystkie (N)"), grid wyników, refresh, snackbar nowości, stany | 5, 6 |
| Widok systemu: nagłówek z licznikami, szukajka lokalna, chipy 3, sortowanie, grid | 7 |
| Karta gry: hero z rozmyciem, wstecz, pigułki, sekcje, przyklejony przycisk, wolne miejsce, offline, usuwanie | 8 |
| Pobierania: nagłówek, karty z okładką/prędkością, akcje, „Zakończone" + „Wyczyść", pusty stan, tap → gra | 3, 9 |
| Ustawienia: karty Serwer/Pobieranie/Urządzenie/O aplikacji, dialog katalogu, uprawnienie, foldery per system, Wi‑Fi | 3, 10 |
| Logowanie | 11 |
| `wifiOnly` + `requiresWiFi`, `GameProgress` bajty/prędkość, `clearFinished` | 3 |
| `buildShelves`, `updatableIdsProvider`, filtr, `systemGamesProvider`, usunięcie `selectedSystemProvider` | 4, 12 |
| Testy: 100%, router, widgety, e2e | każdy task + 12, 13 |
| Wersja 0.2.0, brak nowych zależności | 10, 13 |
