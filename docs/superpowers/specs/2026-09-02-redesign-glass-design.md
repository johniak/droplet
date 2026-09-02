# Droplet — redesign aplikacji („Glass")

Data: 2026-09-02. Dotyczy wyłącznie aplikacji Flutter (`app/`). Backend i kontrakt API
bez zmian.

## 1. Po co

Obecny interfejs (M4–M6) jest funkcjonalny, ale surowy: płaska szata, brak widocznego
przycisku wstecz na karcie gry, pasek statusu ginie na jasnych okładkach, biblioteka to
jeden grid z rzędem chipów. Cel: wygląd współczesnego launchera konsolowego (klimat
PS5 / eShop) przy zachowaniu całej logiki z `core/*`, bramki 100% pokrycia i testów e2e.

Wybrany kierunek wizualny: **Glass** — granatowy gradient tła, półprzezroczyste
powierzchnie, pływająca dolna nawigacja, gradientowy przycisk główny, na karcie gry
rozmyta okładka jako tło i ostra okładka na wierzchu.

## 2. Decyzje

| Temat | Decyzja |
|---|---|
| Struktura biblioteki | Ekran główny z półkami (poziome rzędy okładek) per system; widok systemu jako grid |
| Nawigacja | Dolna nawigacja: Biblioteka / Pobierania / Ustawienia, każda z własnym stosem |
| Zakres zmian w kodzie | Wymiana warstwy widoków (`features/*`, `app/*`); `core/*` bez zmian poza Wi‑Fi i prędkością |
| Rozmycie (`BackdropFilter`) | Tylko dolna nawigacja i tło hero na karcie gry; karty w listach bez rozmycia |
| Nowe funkcje | Prędkość i pozostały rozmiar pobierania, sekcja „Zakończone", chip „Do aktualizacji", status serwera z licznikami, wolne miejsce w ustawieniach, „Tylko Wi‑Fi" |
| Świadomie pominięte | Licznik zajętego miejsca przez ROMy, menu „⋯" na karcie gry, powitanie użytkownika |
| Wersja aplikacji | `0.2.0` |

## 3. System wizualny

Plik `app/lib/app/tokens.dart` (stałe) i `app/lib/app/theme.dart` (`ThemeData`).

Kolory:

| Token | Wartość | Użycie |
|---|---|---|
| `kBgTop` | `#1E2A55` | początek gradientu tła (lewy górny róg) |
| `kBgMid` | `#0D1020` | środek gradientu |
| `kBgBottom` | `#090B14` | koniec gradientu, tło nagłówków przyklejonych |
| `kAccent` | `#7C9DFF` | akcent: zaznaczenia, aktywna zakładka, odznaki |
| `kAccentAlt` | `#9B6BFF` | drugi kolor gradientu przycisku głównego |
| `kText` | `#EEF1FF` | tekst główny |
| `kTextDim` | `#8E96B8` | tekst drugorzędny |
| `kDanger` | `#FF8A8A` | błędy |
| `kOk` | `#5BE0A0` | kropka statusu „połączono" |
| `kGlass` | biały α 0.07 | wypełnienie kart |
| `kGlassBorder` | biały α 0.10 | obrys kart |

Kształty: promień kart 14, promień okładek 12, dolna nawigacja 26 (pigułka), przycisk
główny 14, okrągłe przyciski ikon 36 px. Typografia: domyślna rodzina systemowa,
tytuł ekranu 22/700, tytuł gry 22/700 wyśrodkowany, etykiety sekcji 11/600 wersalikami
z rozstrzeleniem 1.2, tekst listy 14, drugorzędny 12.

Tło ekranu: `AppBackground` — `DecoratedBox` z gradientem radialnym (`kBgTop` w lewym
górnym rogu → `kBgMid` → `kBgBottom`); każdy `Scaffold` ma `backgroundColor:
Colors.transparent` i jest owinięty tym widgetem (w powłoce nawigacyjnej, raz).

Wspólne widgety (`app/lib/app/widgets/`):

- `GlassPanel` — kontener z `kGlass`, obrysem `kGlassBorder`, promieniem 14; bez rozmycia.
- `GlassBar` — dolna nawigacja: pigułka z `BackdropFilter(blur 16)`, trzy pozycje
  z ikoną i podpisem, odznaka z liczbą aktywnych pobierań na „Pobierania".
- `PrimaryButton` — pełna szerokość, 48 px, gradient `kAccent → kAccentAlt`, cień
  w kolorze akcentu; wariant `ghost` (wypełnienie `kGlass`) na akcje drugorzędne.
- `CircleIconButton` — 36 px, tło czarne α 0.45 z obrysem `kGlassBorder`; używany na
  wstecz, sortowanie, akcje w pobieraniach.
- `Pill` — pigułka z tekstem (system, rozmiar, stan); wariant `accent`.
- `SectionLabel` — etykieta sekcji z opcjonalnym tekstem po prawej.
- `PulseBox` — zostaje (skeleton), kolor na `kGlass`.

Pasek statusu: `SystemUiOverlayStyle.light` globalnie (`AppBar.systemOverlayStyle`
albo `AnnotatedRegion` w powłoce). Hero karty gry ma dodatkowo gradient czarny α 0.5 →
przezroczysty na górnych 80 px, żeby ikony paska były czytelne na jasnej okładce.

## 4. Nawigacja

`go_router` `StatefulShellRoute.indexedStack` z trzema gałęziami:

```
/login                          LoginScreen (poza powłoką)
shell (GlassBar)
  ├─ /                          HomeScreen
  │    ├─ system/:code          SystemScreen
  │    └─ game/:id              GameDetailScreen
  ├─ /downloads                 DownloadsScreen
  └─ /settings                  SettingsScreen
       └─ folders               FoldersScreen
```

- Ścieżka `game/:id` jest w gałęzi Biblioteki: wejście z półki daje stos
  `[/, /game/7]`, wejście z widoku systemu `[/, /system/snes, /game/7]`; systemowe
  wstecz cofa o jeden ekran, nigdy nie zamyka aplikacji z karty gry.
- Z ekranu Pobierania tap w kartę robi `context.go('/game/:id')`, co przełącza gałąź
  na Bibliotekę (zgodnie z zachowaniem `go` w powłoce).
- Redirect logowania bez zmian (`refreshListenable` na sesji).
- Dolna nawigacja jest ukryta na karcie gry (pełnoekranowy hero i przyklejony przycisk
  na dole); na pozostałych ekranach gałęzi jest widoczna. Realizacja: `GlassBar`
  sprawdza `GoRouterState.of(context).matchedLocation` i chowa się dla `/game/`.
- Klucze testowe: `nav-library`, `nav-downloads`, `nav-settings`, `back-button`.

## 5. Ekrany

### 5.1 Ekran główny (`HomeScreen`)

Kolejność od góry:

1. Nagłówek: wordmark „Droplet" (22/700), po prawej `CircleIconButton` sortowania
   (dotyczy gridu wyników i widoku systemu; ten sam `sortProvider`).
2. Szukajka (`GlassPanel` w kształcie pigułki, ikona lupy, podpowiedź „Szukaj w
   bibliotece").
3. Pastylka offline „Tryb offline — pokazuję ostatnio pobraną bibliotekę", gdy
   `isOfflineProvider` jest prawdą.
4. Gdy zapytanie jest puste — półki:
   - „Ostatnio dodane": 10 gier o najwyższym `id`, duże okładki (szerokość 120).
   - „Na urządzeniu": gry z `installedIdsProvider`; półka ukryta, gdy zbiór pusty.
   - Jedna półka na każdy system z `systemsProvider`, w kolejności z API, nagłówek
     `nazwa systemu` + `liczba gier ›`; tap w nagłówek → `/system/:code`.
     Półka pokazuje do 12 okładek (szerokość 96) plus kafel „Wszystkie (N)" na końcu.
5. Gdy zapytanie niepuste — półki znikają, pojawia się grid wyników z całej biblioteki
   (ten sam widget gridu co w widoku systemu) z nagłówkiem „Wyniki · N".

Pull-to-refresh na całej liście (`RefreshIndicator` → invalidate snapshotu). Snackbar
„Nowe w bibliotece: N gier" bez zmian. Stany: skeleton z trzema półkami `PulseBox`,
błąd z „Ponów", pusta biblioteka z komunikatem jak dziś.

Dane: nowy provider `homeShelvesProvider` liczący `recent`, `installed` i mapę
`systemCode → List<GameSummary>` z `librarySnapshotProvider`, `installedIdsProvider`
i `sortProvider` (czysta funkcja `buildShelves(...)` testowana jednostkowo).

### 5.2 Widok systemu (`SystemScreen`)

- Nagłówek: `CircleIconButton` wstecz, nazwa systemu, pod spodem „N gier · M na
  urządzeniu", po prawej sortowanie.
- Szukajka „Szukaj w {system}" (własny stan lokalny ekranu, nie globalny
  `searchQueryProvider`).
- Chipy: „Wszystkie", „Na urządzeniu", „Do aktualizacji" (jednokrotny wybór).
  „Do aktualizacji" filtruje po nowym `updatableIdsProvider` (zasilany przez karty
  gier tak samo jak `installedIdsProvider`, z pola `updateAvailable`).
- Grid 2 kolumny, `childAspectRatio` 0.58, kafel: okładka 3:4 z odznaką stanu
  (✓ zainstalowana, ↓ aktualizacja, ◔ częściowa), tytuł 2 linie, rozmiar 12/dim.
- `installedOnlyProvider` zostaje (chip „Na urządzeniu"), `selectedSystemProvider`
  przestaje być potrzebny i znika wraz z testami.

### 5.3 Karta gry (`GameDetailScreen`)

- `CustomScrollView`; hero 260 px: warstwy od dołu: rozmyta okładka
  (`ImageFiltered` blur 22, `fit: cover`, nasycenie przez `ColorFiltered`), gradient
  do `kBgMid` na dolnych 120 px, gradient czarny → przezroczysty na górnych 80 px,
  ostra okładka 3:4 o wysokości 150 wyśrodkowana przy dolnej krawędzi (cień, obrys
  `kGlassBorder`, `Hero` tag `cover-{id}` jak dziś), `CircleIconButton` wstecz w
  lewym górnym rogu pod paskiem statusu (`SafeArea`). Bez okładki: rozmyte tło z
  gradientu placeholdera, na wierzchu placeholder z tytułem.
- Tytuł 22/700 wyśrodkowany, pod nim wiersz pigułek: system, `formatBytes(total)`,
  stan: „Zainstalowana" (accent), „Jest aktualizacja" (accent), „Częściowo", brak
  pigułki gdy nic nie ma na dysku.
- Sekcje plików jak dziś (Gra / Aktualizacja / DLC / Płyta N / Pozostałe); wiersz to
  `GlassPanel` z kwadratowym zaznaczeniem po lewej, nazwą pliku (1 linia, elipsa),
  wersją jako drugą linią dim, rozmiarem po prawej; niezaznaczony wiersz α 0.55.
  Sekcja „Aktualizacja" ma po prawej etykietę „najnowsza domyślnie".
- Dolny pasek przyklejony (`bottomNavigationBar` Scaffoldu z gradientem do tła):
  `PrimaryButton` z tekstem „Pobierz · X" / „Pobierz aktualizację · X" /
  dla zainstalowanej bez aktualizacji `ghost` „Usuń z urządzenia"; gdy coś jest na
  dysku i jest co pobrać, pod przyciskiem głównym mniejszy tekstowy „Usuń z
  urządzenia". Linia pod przyciskiem: „Wolne X · zapis: {dirFor(system)}" (wolne
  z `DownloaderPort.freeBytes`; gdy null, tylko katalog). Offline: przycisk
  nieaktywny, linia „Offline — pobieranie niedostępne".
- Obsługa błędów pobierania (uprawnienie, miejsce) bez zmian: snackbar.

### 5.4 Pobierania (`DownloadsScreen`)

- Nagłówek: „Pobierania", pod spodem „N aktywnych · pozostało X" (suma
  `bytesTotal - bytesDone` po aktywnych), gdy nic nie leci: „Brak aktywnych".
- Lista `GlassPanel` kart: miniatura okładki 40×52 (`CoverImage`, `size: thumb`),
  tytuł, druga linia: `{pobrano} / {rozmiar} · {prędkość}` dla running, „Wstrzymane"
  dla paused, „Błąd: {komunikat}" (kDanger) dla failed, „Gotowe · {rozmiar}" dla
  complete; pasek postępu gradientowy 5 px; akcje jako `CircleIconButton`:
  running → pauza, anuluj; paused → wznów, anuluj; failed → ponów; complete → ✓.
- Sekcja „Zakończone" (`SectionLabel` z akcją „Wyczyść") zbiera wpisy `complete`
  i `failed`; „Wyczyść" usuwa wpisy `complete` z mapy postępu (`DownloadManager.
  clearFinished()`); wpisy `failed` zostają do skutku (ponów lub anuluj).
- Pusty stan: ikona strzałki w `GlassPanel`, „Brak pobierań", „Wybierz grę i
  naciśnij Pobierz".
- Tap w kartę → `/game/:id`.

Zmiany w `core/downloads/download_manager.dart`: `GameProgress` dostaje
`systemCode`, `hasCover`, `bytesDone`, `bytesTotal`, `speedBytesPerSec` (z
`TaskProgressUpdate.networkSpeed`, MB/s → B/s; `-1` gdy nieznana → `null`);
`_onUpdate` sumuje bajty po plikach gry; nowe `clearFinished()`.

### 5.5 Ustawienia (`SettingsScreen`, `FoldersScreen`)

Karty `GlassPanel` z wierszami:

- **Serwer**: kropka `kOk` „Połączono" / `kTextDim` „Offline" (z
  `isOfflineProvider`), adres serwera, „N gier · M systemów" ze snapshotu;
  wiersz „Wyloguj".
- **Pobieranie**: „Katalog ROMów" z bieżącą ścieżką i akcją „Zmień" otwierającą
  dialog z polem tekstowym (`Key('base-dir-field')`) i przyciskami Anuluj/Zapisz;
  „Dostęp do plików" ze stanem i przyciskiem „Przyznaj" (`Key('grant-permission')`)
  gdy brak; „Foldery per system" z podsumowaniem kodów → `/settings/folders`;
  „Pobieraj tylko po Wi‑Fi" z przełącznikiem (`Key('wifi-only')`).
- **Urządzenie**: „Wolne miejsce" (z `freeBytes(baseDir)`, „—" gdy null).
- **O aplikacji**: „Droplet {appVersion}", po prawej „API v1".

`FoldersScreen`: nagłówek z wstecz „Foldery per system", lista pól (klucze
`system-dir-{code}` jak dziś), zapis przy każdej zmianie jak dziś.

`StorageSettings` dostaje `wifiOnly` (klucz `storage.wifi_only`, domyślnie false),
repozytorium `saveWifiOnly(bool)`, `buildTask` ustawia `requiresWiFi: settings.
wifiOnly`.

### 5.6 Logowanie (`LoginScreen`)

Znak aplikacji (kwadrat 64 z promieniem 20, gradient przycisku, ikona kropli),
„Droplet" 24/700, podtytuł dim, formularz w `GlassPanel`: trzy pola z etykietami w
polu, `PrimaryButton` „Zaloguj" (w trakcie: wskaźnik 20 px), błąd `kDanger` pod
przyciskiem, stopka dim „Hasło zostaje na telefonie, appka trzyma tylko token."
Walidacja i obsługa błędów bez zmian.

## 6. Dane i providery — podsumowanie zmian

| Miejsce | Zmiana |
|---|---|
| `features/library/providers.dart` | + `buildShelves`, `homeShelvesProvider`, `updatableIdsProvider`; − `selectedSystemProvider`; `gamesProvider` przyjmuje system jako parametr rodziny (`gamesForSystemProvider(code?)`) |
| `core/downloads/download_manager.dart` | `GameProgress` + pola bajtów/prędkości/okładki, `clearFinished()` |
| `core/downloads/storage_settings.dart` | `wifiOnly` + zapis |
| `core/downloads/task_builder.dart` | `requiresWiFi` |
| `features/settings/settings_screen.dart` | `appVersion = '0.2.0'` |
| `pubspec.yaml` | `version: 0.2.0+2` |

Bez nowych zależności.

## 7. Wydajność

- `BackdropFilter` tylko w `GlassBar` (jeden na ekran) i nigdzie w przewijanych
  listach.
- Rozmyte tło hero to `ImageFiltered` na jednym obrazie: ten sam `ImageProvider`
  co ostra okładka, więc obraz pobiera się raz. Półki i grid używają rozmiaru
  `thumb`, hero rozmiaru `full`, jak dziś.
- Półki to `ListView.builder` poziome wewnątrz `SliverList`; kafle mają stałą
  szerokość, brak `IntrinsicWidth`.

## 8. Testy

- Bramka 100% pokrycia (`scripts/check_coverage_app.sh`) i lista dozwolonych
  wyłączeń bez zmian.
- Testy widgetowe: nowe pliki dla `HomeScreen`, `SystemScreen`, `GameDetailScreen`,
  `DownloadsScreen`, `SettingsScreen`, `FoldersScreen`, `LoginScreen`, `GlassBar`
  i pozostałych wspólnych widgetów; usunięte testy chipów systemowych. Każdy stan
  (loading / error / empty / data / offline) i każda gałąź akcji ma test.
- Testy jednostkowe: `buildShelves`, filtr „Do aktualizacji", sumowanie bajtów i
  prędkości w `DownloadManager`, `clearFinished`, `wifiOnly` w ustawieniach i
  `requiresWiFi` w tasku.
- Test routera: stos gałęzi (wstecz z `/system/snes/…` wraca do systemu), ukrycie
  paska na `/game/`, przełączanie gałęzi z `/downloads` do `/game/:id`.
- E2E (`integration_test/`): `app_flow_test` — logowanie, półka „Nintendo Switch"
  → nagłówek półki → widok systemu → „Hollow Knight" → karta gry z sekcją
  „Aktualizacja" → `back-button` → `nav-settings` → „Wyloguj". `download_flow_test`
  — `nav-settings` → „Zmień" → `base-dir-field` w dialogu → „Zapisz" →
  `nav-library` → „Super Mario World" z półki → „Pobierz" → oczekiwanie na
  „Zainstalowana" → „Usuń z urządzenia" → „Usuń" → z powrotem „Pobierz".
- Akceptacja wizualna na urządzeniu: pasek statusu czytelny na jasnej okładce,
  wstecz widoczny na każdym ekranie poza głównym, dolna nawigacja nie zasłania
  ostatniego wiersza list (dolny padding = wysokość paska + margines).
