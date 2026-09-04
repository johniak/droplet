# M12 — Gamepad: pełna obsługa pada w aplikacji

Data: 2026-09-04. Aplikacja Android (Flutter + Kotlin); serwer bez zmian.
Urządzenie referencyjne: AYN Thor (wbudowany pad w układzie Xbox, Android 13).

## 1. Cel

Całą aplikację da się obsłużyć padem bez dotykania ekranu: nawigacja fokusem
(D-pad i lewa gałka), aktywacja (A), wstecz (B), skróty globalne (L1/R1
zakładki, Y szukaj, Select ustawienia, Start główna akcja), przewijanie prawą
gałką. Fokus jest zawsze widoczny i zawsze na czymś sensownym.

## 2. Warstwa wejścia

### 2.1 Natywnie (Kotlin, `MainActivity`)
- `onGenericMotionEvent`: źródło `SOURCE_JOYSTICK`/`SOURCE_GAMEPAD`.
  Lewa gałka `AXIS_X/AXIS_Y` i HAT `AXIS_HAT_X/AXIS_HAT_Y` → syntetyczne
  `KeyEvent` D-pada (`KEYCODE_DPAD_LEFT/RIGHT/UP/DOWN`) wysyłane przez
  `dispatchKeyEvent`. Martwa strefa 0.5; kierunek trzymany → pierwsze
  powtórzenie po 400 ms, kolejne co 120 ms (Handler); puszczenie → `ACTION_UP`
  i stop powtarzania. Prawa gałka `AXIS_Z/AXIS_RZ` → `KEYCODE_PAGE_UP/PAGE_DOWN`
  (oś pionowa; ta sama martwa strefa i repeat; pozioma ignorowana).
- Jeżeli urządzenie samo tłumaczy gałkę na D-pad (przychodzą prawdziwe
  `KEYCODE_DPAD_*` z tego samego `deviceId`), syntetyczne nie są generowane
  podwójnie: syntetyczne zdarzenia mają `source = SOURCE_KEYBOARD` i flagę
  `FLAG_SOFT_KEYBOARD`? Nie — używamy prostszej zasady: syntetyk powstaje tylko
  z osi; HAT jest osią, więc D-pad zgłaszany jako HAT też przez to przechodzi,
  a D-pad zgłaszany jako klawisze omija ten kod. Brak dublowania.
- Wszystkie `KEYCODE_BUTTON_*`, `DPAD_*`, `PAGE_*` trafiają do Fluttera
  normalną drogą (bez zmian).

### 2.2 Flutter — skróty globalne (`lib/app/input/gamepad.dart`)
`Shortcuts` + `Actions` zawieszone w `AppShell` (nad `shell`), więc działają
we wszystkich zakładkach; ekran gry (poza paskiem) też jest pod shellem.

| Klawisz (`LogicalKeyboardKey`) | Intent | Akcja |
|---|---|---|
| `gameButtonLeft1` | `PreviousTabIntent` | `shell.goBranch((i-1) mod 3)` |
| `gameButtonRight1` | `NextTabIntent` | `shell.goBranch((i+1) mod 3)` |
| `gameButtonY` | `FocusSearchIntent` | fokus na pole szukania bieżącego ekranu (Home/System), gdzie indziej nic |
| `gameButtonSelect` | `OpenSettingsIntent` | `goBranch(2)` |
| `gameButtonStart` | `PrimaryActionIntent` | ekran gry: Play jeśli jest, inaczej Download; poza ekranem gry nic |
| `gameButtonA` | `ActivateIntent` | domyślne Fluttera (już działa) |
| `gameButtonB` | — | Android zamienia na Back; pola tekstowe: zdejmujemy fokus zamiast wpisywać |
| `arrow*` / D-pad | `DirectionalFocusIntent` | domyślne Fluttera |
| `pageUp/pageDown` | `ScrollIntent` | domyślne Fluttera (prawa gałka) |

`FocusSearchIntent` i `PrimaryActionIntent` są obsługiwane przez ekrany:
Home/System rejestrują `Actions` z `FocusSearchAction`, ekran gry
`PrimaryActionAction`. Rejestracja przez zwykłe `Actions(actions: {...})` w
drzewie ekranu (Flutter szuka akcji od elementu z fokusem w górę — dlatego
fokus zawsze musi być wewnątrz ekranu, patrz §4).

Pure Dart: `GamepadIntent? intentFor(LogicalKeyboardKey key)` zwraca typ
intentu dla klawisza (testowalne bez widgetów).

## 3. Fokus widoczny: `FocusGlow`

`lib/app/widgets/focus_glow.dart` — jeden wrapper dla każdej interaktywnej
powierzchni:

```dart
FocusGlow(
  onTap: ...,          // wymagane; wywoływane też przez ActivateIntent (A)
  autofocus: false,
  focusNode: null,
  borderRadius: kRadiusCover,
  scale: 1.04,         // powiększenie z fokusem; 1.0 dla wierszy list
  child: ...,
)
```

- `FocusableActionDetector` (fokus + `ActivateIntent` → `onTap`) + `InkWell`
  (dotyk); brak `GestureDetector` w interaktywnych miejscach.
- Wygląd z fokusem: obwódka 2 px `kAccent` z zewnętrzną poświatą
  (`BoxShadow` `kAccent` α 0.45, blur 14) i `AnimatedScale` (150 ms).
  Bez fokusu: nic (nie ma podwójnej ramki z systemowym highlightem —
  `focusColor: Colors.transparent` w InkWell).
- Po otrzymaniu fokusu: `Scrollable.ensureVisible(context, alignment: 0.5,
  duration: 200 ms)` — działa dla list pionowych i półek poziomych
  (`ensureVisible` wspina się po wszystkich Scrollable).
- Zastosowanie: `CoverThumb`/`GameTile`/`ShelfCard`/kafelek „All” w półce,
  nagłówek półki (tap otwiera system), `SettingsRow`, `GlassPanel` z `onTap`,
  wiersze plików na ekranie gry (`_FileRow`), chipy filtrów, pozycje `GlassBar`,
  wiersze Downloads, `_ModsHint` Copy path (to `TextButton` — zostaje).
- `PrimaryButton`, `CircleIconButton`, `TextButton`, `Checkbox`, `Switch`,
  `DropdownButton` są już fokusowalne; dostają spójny wygląd przez motyw:
  `focusColor`/`overlayColor` z `kAccent` α 0.18 i obwódka przez
  `WidgetStateProperty` na `side` (`OutlinedBorder`). `DropdownButton`:
  `focusColor: kGlass`.

## 4. Gdzie fokus startuje i jak wędruje

- Każdy ekran ma `FocusTraversalGroup(policy: ReadingOrderTraversalPolicy())`;
  półka pozioma to własna grupa, żeby lewo/prawo nie wyskakiwało z półki.
- **Home**: `autofocus` na pierwszym kafelku pierwszej półki (po załadowaniu
  danych); gdy biblioteka pusta: przycisk „Retry”/nic. Pole szukania **nie**
  ma `autofocus` i nie odzyskuje fokusu po powrocie z ekranu gry: przy tapie
  na kafelek `FocusManager.instance.primaryFocus?.unfocus()` przed nawigacją,
  a ekran gry ustawia własny fokus. Z ostatniej półki dół → `GlassBar`.
- **System**: pierwszy kafelek siatki; chipy filtrów w kolejności czytania
  nad siatką; przycisk wstecz przez B.
- **Ekran gry**: fokus na głównym przycisku: Play jeśli jest, inaczej
  Download (albo Delete gdy zainstalowana bez emulatora); lista plików nad
  paskiem osiągalna górą.
- **Downloads**: pierwszy wiersz; Pause/Cancel w wierszu przez fokus na
  przyciskach.
- **Settings / Folders / Emulators**: pierwszy wiersz karty. Dropdown: A
  otwiera menu, D-pad wybiera, A zatwierdza, B zamyka (natywne zachowanie
  `DropdownButton`).
- **Dialogi** (`AlertDialog`): `autofocus` na akcji potwierdzającej (Save /
  Delete), B zamyka (Navigator.pop przez Back).
- **Pole szukania**: fokus tylko przez Y albo dotyk; Y drugi raz nie zmienia
  nic; B lub „Done” chowa klawiaturę i przenosi fokus na pierwszy kafelek
  wyników (jeśli są) albo z powrotem na pierwszą półkę. Implementacja:
  `SearchField` ma `FocusNode` z `onKeyEvent`: `gameButtonB`/`escape` →
  `unfocus()` + `KeyEventResult.handled`.
- `GlassBar`: pozycje w jednej grupie; lewo/prawo między zakładkami, góra
  wraca do treści; A wybiera.

## 5. Ustawienia → Controller

Karta „Controller” w Settings (sekcja po „Emulators”): statyczna lista
skrótów z §2.2 w dwóch kolumnach (`Row` z `Expanded`), bez wykrywania pada.

## 6. Poza zakresem (świadomie)
- Pełnoekranowa klawiatura systemowa w poziomie (extract UI) — zależy od IME;
  nie ruszamy.
- Mapowanie przycisków konfigurowalne przez użytkownika.
- Wibracje.

## 7. Testy i bramki
- Dart: `intentFor` dla wszystkich klawiszy z tabeli i klawisza spoza niej;
  `FocusGlow`: fokus rysuje obwódkę, A wywołuje `onTap`, dotyk wywołuje
  `onTap`, `ensureVisible` przewija (kafelek poza ekranem staje się widoczny
  po `requestFocus`); Home: po załadowaniu fokus na pierwszym kafelku, strzałka
  w prawo przenosi na drugi, dół do następnej półki, Y fokusuje pole szukania,
  B w polu szukania zdejmuje fokus; shell: L1/R1/Select zmieniają zakładkę;
  ekran gry: autofocus na Play/Download, Start wywołuje właściwą akcję;
  Settings: pierwszy wiersz ma fokus, karta Controller widoczna.
  Klawisze przez `tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA)` itd.
  100% linii, `flutter analyze` czysto.
- Kotlin: nietestowany jednostkowo; weryfikacja na Thorze: gałka porusza
  fokusem, prawa gałka przewija, A/B/L1/R1/Y/Start/Select działają.
- E2E na emulatorze: `app_flow_test`: po zalogowaniu `sendKeyEvent` strzałek
  i A otwiera pierwszą grę; L1/R1 zmienia zakładkę.
- Wersja `0.7.0+15`.
