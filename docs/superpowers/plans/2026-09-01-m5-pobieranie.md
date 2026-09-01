# M5 — Pobieranie na urządzenie: plan implementacji

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pełna pętla wartości: wybór plików na karcie gry → pobieranie w tle z pauzą/wznowieniem i powiadomieniami → ROM ląduje w katalogu RetroArch → stan „zainstalowane" w UI → usuwanie lokalnych ROMów bez dotykania save'ów.

**Architecture:** `background_downloader` (kolejka, powiadomienia, wznawianie przez Range, plik tymczasowy + przeniesienie po sukcesie); ustawienia ścieżek w `shared_preferences` (katalog bazowy + mapa podkatalogów per system); uprawnienie All Files Access (`MANAGE_EXTERNAL_STORAGE`) przez `permission_handler`; logika czysta (wybór plików, budowa ścieżek, diff manifest↔dysk) w `lib/core/downloads/` — unit-testowalna bez Fluttera i bez dysku.

**Tech Stack:** dodatkowo: `background_downloader`, `shared_preferences`, `permission_handler`.

**Spec:** `docs/superpowers/specs/2026-09-01-droplet-design.md` (§3.7); API: plan M3.

## Global Constraints

- Obowiązują Global Constraints z M4 — w tym **pokrycie 100%** (`./scripts/check_coverage_app.sh` przy każdym zadaniu) i **suita e2e** (`app/integration_test/` przez `scripts/e2e_app.sh`).
- Usuwanie NIGDY nie wychodzi poza pliki wymienione w manifeście gry — żadnego kasowania katalogów rekurencyjnie.
- Weryfikacja po pobraniu: rozmiar lokalny == `size` z manifestu; niezgodność = pobranie oznaczone jako błędne.
- Stan „zainstalowane" liczony wyłącznie z porównania nazwa+rozmiar (bez hashy).
- Domyślny wybór plików: base + najnowszy update + wszystkie DLC + wszystkie płyty + support; starsze updaty odznaczone.
- `AndroidManifest.xml`: `<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>` + `POST_NOTIFICATIONS`.

---

### Task 1: Ustawienia ścieżek (katalog bazowy + per system)

**Files:**
- Create: `app/lib/core/downloads/storage_settings.dart`
- Modify: `app/pubspec.yaml` (`flutter pub add background_downloader shared_preferences permission_handler`)
- Test: `app/test/core/storage_settings_test.dart`

**Interfaces:**
- Produces:

```dart
class StorageSettings {
  StorageSettings(this.baseDir, this.systemDirs);
  final String baseDir;                       // np. /storage/emulated/0/RetroArch/roms
  final Map<String, String> systemDirs;       // code -> podkatalog; brak wpisu = code
  String dirFor(String systemCode);           // baseDir/podkatalog
  String pathFor(String systemCode, String fileName);
}
class StorageSettingsRepository {
  StorageSettingsRepository(SharedPreferencesAsync prefs);
  Future<StorageSettings> load();             // default baseDir: /storage/emulated/0/RetroArch/roms
  Future<void> saveBaseDir(String dir);
  Future<void> saveSystemDir(String code, String dir);
}
// provider: storageSettingsProvider = FutureProvider<StorageSettings>
```

- [ ] **Step 1: Failing testy**

`app/test/core/storage_settings_test.dart`:

```dart
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dirFor falls back to system code', () {
    final s = StorageSettings('/roms', {'psx': 'PlayStation'});
    expect(s.dirFor('psx'), '/roms/PlayStation');
    expect(s.dirFor('snes'), '/roms/snes');
  });

  test('pathFor joins dir and filename', () {
    final s = StorageSettings('/roms', {});
    expect(s.pathFor('snes', 'Mario (USA).sfc'), '/roms/snes/Mario (USA).sfc');
  });
}
```

- [ ] **Step 2: FAIL** — `flutter test test/core/storage_settings_test.dart`

- [ ] **Step 3: Implementacja** — czysta klasa + repozytorium na `SharedPreferencesAsync` (klucze `storage.base_dir`, `storage.system_dirs` jako JSON). Provider w tym samym pliku.

- [ ] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: storage settings with per-system directories"`

---

### Task 2: Uprawnienia + sekcja „Pobieranie" w ustawieniach

**Files:**
- Create: `app/lib/core/downloads/permissions.dart`
- Modify: `app/lib/features/settings/settings_screen.dart`, `app/android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Produces: `ensureStoragePermission() -> Future<bool>` (`Permission.manageExternalStorage.request()`; na odmowę — `openAppSettings()`); w ustawieniach sekcja **Pobieranie**: edycja katalogu bazowego (pole tekstowe z `Key('base-dir-field')` — używane przez e2e — + walidacja że istnieje/da się utworzyć), lista systemów z edycją podkatalogu, status uprawnienia z przyciskiem „Przyznaj".

- [ ] **Step 1: Manifest + implementacja** — wg Interfaces; do manifestu dwa `uses-permission` z Global Constraints.

- [ ] **Step 2: Weryfikacja ręczna na telefonie** — przyznanie uprawnienia przechodzi przez systemowy ekran i wraca ze statusem `granted`; utworzenie katalogu bazowego działa.

- [ ] **Step 3: Commit** — `git commit -m "feat: storage permission flow and download settings section"`

---

### Task 3: Domyślny wybór plików do pobrania

**Files:**
- Create: `app/lib/core/downloads/selection.dart`
- Test: `app/test/core/selection_test.dart`

**Interfaces:**
- Produces:

```dart
Set<int> defaultSelection(List<GameFileModel> files);
// zasady: base, dlc, disc, support, other -> zawsze zaznaczone;
// update -> tylko plik z najwyższą wersją (porównanie po liczbie wyciągniętej
// z version, np. "v196608" -> 196608; brak liczby = 0)
int versionNumber(String version);
```

- [ ] **Step 1: Failing testy**

`app/test/core/selection_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/selection.dart';
import 'package:flutter_test/flutter_test.dart';

GameFileModel f(int id, FileRole role, {String version = ''}) => GameFileModel(
    id: id, name: 'f$id', relativePath: 'p/f$id', role: role,
    discNumber: null, version: version, size: 1);

void main() {
  test('versionNumber extracts digits', () {
    expect(versionNumber('v196608'), 196608);
    expect(versionNumber('v1.2.6'), 126);
    expect(versionNumber(''), 0);
  });

  test('only newest update selected', () {
    final sel = defaultSelection([
      f(1, FileRole.base),
      f(2, FileRole.update, version: 'v65536'),
      f(3, FileRole.update, version: 'v196608'),
      f(4, FileRole.dlc),
    ]);
    expect(sel, {1, 3, 4});
  });

  test('discs and support always selected', () {
    final sel = defaultSelection([
      f(1, FileRole.disc), f(2, FileRole.disc), f(3, FileRole.support),
    ]);
    expect(sel, {1, 2, 3});
  });
}
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja**

`app/lib/core/downloads/selection.dart`:

```dart
import '../api/models.dart';

int versionNumber(String version) {
  final digits = version.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? 0 : int.parse(digits);
}

Set<int> defaultSelection(List<GameFileModel> files) {
  final selected = <int>{};
  GameFileModel? newestUpdate;
  for (final file in files) {
    if (file.role == FileRole.update) {
      if (newestUpdate == null ||
          versionNumber(file.version) > versionNumber(newestUpdate.version)) {
        newestUpdate = file;
      }
    } else {
      selected.add(file.id);
    }
  }
  if (newestUpdate != null) selected.add(newestUpdate.id);
  return selected;
}
```

- [ ] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: default file selection with newest-update rule"`

---

### Task 4: Diff manifest ↔ dysk (stan zainstalowania)

**Files:**
- Create: `app/lib/core/downloads/local_state.dart`, `app/lib/core/downloads/local_scanner.dart`
- Test: `app/test/core/local_state_test.dart`

**Interfaces:**
- Produces:

```dart
enum InstallStatus { none, partial, installed }

class LocalGameState {
  final InstallStatus status;
  final bool updateAvailable;        // base jest, a najnowszy update z serwera nie
  final List<GameFileModel> missing; // z domyślnej selekcji
  final List<String> presentPaths;   // absolutne ścieżki istniejących plików gry
}

LocalGameState diffGame(
  List<GameFileModel> files,          // manifest z serwera
  Map<String, int> localSizesByName,  // basename -> rozmiar (z katalogu systemu)
  StorageSettings settings,
  String systemCode,
);

// local_scanner.dart (jedyne miejsce dotykające dysku):
Future<Map<String, int>> scanSystemDir(String dirPath); // {} gdy katalog nie istnieje
```

Reguły `diffGame`: rozpatrywana jest tylko domyślna selekcja (`defaultSelection`); plik „jest" gdy nazwa i rozmiar się zgadzają; wszystkie są → `installed`; żaden → `none`; część → `partial`; `updateAvailable` gdy base obecny, a najnowszy update nieobecny; `presentPaths` obejmuje też pliki spoza selekcji (np. stary update na dysku) — to lista do usuwania.

- [ ] **Step 1: Failing testy**

`app/test/core/local_state_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:flutter_test/flutter_test.dart';

GameFileModel f(int id, String name, FileRole role,
        {String version = '', int size = 10}) =>
    GameFileModel(id: id, name: name, relativePath: 'sw/$name', role: role,
        discNumber: null, version: version, size: size);

final settings = StorageSettings('/roms', {});

void main() {
  final files = [
    f(1, 'hk.nsp', FileRole.base),
    f(2, 'upd.nsp', FileRole.update, version: 'v2'),
  ];

  test('all present -> installed', () {
    final s = diffGame(files, {'hk.nsp': 10, 'upd.nsp': 10}, settings, 'switch');
    expect(s.status, InstallStatus.installed);
    expect(s.updateAvailable, false);
  });

  test('none present -> none', () {
    final s = diffGame(files, {}, settings, 'switch');
    expect(s.status, InstallStatus.none);
    expect(s.missing.length, 2);
  });

  test('size mismatch means missing', () {
    final s = diffGame(files, {'hk.nsp': 999, 'upd.nsp': 10}, settings, 'switch');
    expect(s.status, InstallStatus.partial);
  });

  test('base without newest update -> updateAvailable', () {
    final s = diffGame(files, {'hk.nsp': 10}, settings, 'switch');
    expect(s.status, InstallStatus.partial);
    expect(s.updateAvailable, true);
  });

  test('presentPaths includes files outside selection', () {
    final withOld = [...files, f(3, 'old-upd.nsp', FileRole.update, version: 'v1')];
    final s = diffGame(withOld, {'hk.nsp': 10, 'old-upd.nsp': 10}, settings, 'switch');
    expect(s.presentPaths, contains('/roms/switch/old-upd.nsp'));
  });
}
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja** — `diffGame` wg reguł (korzysta z `defaultSelection` i `settings.pathFor`); `scanSystemDir` przez `Directory(dirPath).list()` → mapa `basename -> length`.

- [ ] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: manifest-to-disk diff with install status"`

---

### Task 5: Download manager

**Files:**
- Create: `app/lib/core/downloads/download_manager.dart`, `app/lib/core/downloads/task_builder.dart`
- Modify: `app/lib/main.dart` (konfiguracja powiadomień przy starcie)
- Test: `app/test/core/task_builder_test.dart`

**Interfaces:**
- Produces:
  - `task_builder.dart` (czysta logika):

```dart
DownloadTask buildTask({
  required String serverUrl, required Map<String, String> authHeaders,
  required int gameId, required GameFileModel file,
  required StorageSettings settings, required String systemCode,
});
// url: $serverUrl/api/files/${file.id}/download, headers: auth,
// baseDirectory: BaseDirectory.root, directory: settings.dirFor(systemCode) bez wiodącego '/',
// filename: file.name, group: 'game-$gameId', allowPause: true, retries: 3,
// updates: Updates.statusAndProgress, metaData: '{"gameId":$gameId,"size":${file.size}}'
```

  - `download_manager.dart`: `DownloadManager` (provider `downloadManagerProvider`):
    - `Future<void> downloadGame(GameDetail game, Set<int> selectedIds)` — `ensureStoragePermission`, utworzenie katalogu, enqueue tasków (pomija pliki już obecne wg `diffGame`),
    - nasłuch `FileDownloader().updates`: po `TaskStatus.complete` weryfikacja rozmiaru z `metaData` (niezgodność → skasuj plik, oznacz błąd), po czym `ref.invalidate` stanu lokalnego,
    - `pause/resume/cancel(taskId)`, `retryGame(gameId)`,
    - stream postępu per gra: `progressFor(int gameId) -> Stream<double>` (średnia ważona rozmiarami).
  - W `main.dart`: `FileDownloader().configureNotification(running:, complete:, error:, progressBar: true)`.

- [ ] **Step 1: Failing testy**

`app/test/core/task_builder_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/downloads/task_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildTask fills url, path, group and headers', () {
    const file = GameFileModel(id: 42, name: 'Mario (USA).sfc',
        relativePath: 'snes/Mario (USA).sfc', role: FileRole.base,
        discNumber: null, version: '', size: 1024);
    final task = buildTask(
      serverUrl: 'http://nas:8000',
      authHeaders: {'Authorization': 'Token abc'},
      gameId: 7,
      file: file,
      settings: StorageSettings('/storage/emulated/0/RetroArch/roms', {}),
      systemCode: 'snes',
    );
    expect(task.url, 'http://nas:8000/api/files/42/download');
    expect(task.headers['Authorization'], 'Token abc');
    expect(task.directory, 'storage/emulated/0/RetroArch/roms/snes');
    expect(task.filename, 'Mario (USA).sfc');
    expect(task.group, 'game-7');
    expect(task.allowPause, true);
  });
}
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja** — `task_builder.dart` wg Interfaces; `download_manager.dart` jako klasa z wstrzykniętym `FileDownloader` (default `FileDownloader()`), słuchająca `updates` i utrzymująca `Map<int, GameProgress>` eksponowaną przez `StateNotifier`/`Stream`. Weryfikacja rozmiaru: po complete `File(await task.filePath()).length()` vs `size` z `metaData`.

- [ ] **Step 4: PASS** — `flutter test`; build na telefon i szybki test ręczny małego pliku.

- [ ] **Step 5: Commit** — `git commit -m "feat: background download manager with size verification"`

---

### Task 6: Karta gry — pobieranie, usuwanie, badge'e w bibliotece

**Files:**
- Modify: `app/lib/features/game/game_detail_screen.dart`, `app/lib/features/game/providers.dart`, `app/lib/features/library/widgets/game_card.dart`, `app/lib/features/library/providers.dart`
- Create: `app/lib/features/game/delete_dialog.dart`
- Test: `app/test/features/game_actions_test.dart`

**Interfaces:**
- Produces:
  - `localStateProvider = FutureProvider.family<LocalGameState, int>` — `fetchGame` + `scanSystemDir` + `diffGame`.
  - Karta gry: checkboxy przy plikach (start = `defaultSelection`), suma rozmiaru zaznaczonych; przycisk kontekstowy: `none/partial` → „Pobierz (1.4 GB)"; w trakcie → pasek postępu z pauzą; `installed` → „Zainstalowana ✓" + przycisk „Usuń z urządzenia"; `updateAvailable` → dodatkowy przycisk „Pobierz aktualizację".
  - `delete_dialog.dart`: `confirmAndDelete(BuildContext, WidgetRef, LocalGameState) -> Future<bool>` — dialog z listą plików do skasowania i dopiskiem „Save'y i stany zapisu nie zostaną usunięte", kasuje wyłącznie `presentPaths`, potem invaliduje `localStateProvider`.
  - `GameCard`: badge w rogu okładki — `installed` (wypełniona ikona ✓), `partial` (połówkowa), `updateAvailable` (strzałka) — na podstawie `localStateProvider`.

- [ ] **Step 1: Failing testy**

`app/test/features/game_actions_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const detail = GameDetail(
  id: 7, title: 'Mario', systemCode: 'snes', systemName: 'SNES',
  hasCover: false, totalSize: 1024,
  files: [
    GameFileModel(id: 1, name: 'm.sfc', relativePath: 'snes/m.sfc',
        role: FileRole.base, discNumber: null, version: '', size: 1024),
  ],
);

Widget build(LocalGameState state) => ProviderScope(
      overrides: [
        gameDetailProvider(7).overrideWith((ref) async => detail),
        localStateProvider(7).overrideWith((ref) async => state),
      ],
      child: const MaterialApp(home: GameDetailScreen(gameId: 7)),
    );

void main() {
  testWidgets('not installed shows download with size', (tester) async {
    await tester.pumpWidget(build(const LocalGameState(
        status: InstallStatus.none, updateAvailable: false,
        missing: [], presentPaths: [])));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pobierz'), findsOneWidget);
    expect(find.textContaining('1.0 KB'), findsOneWidget);
  });

  testWidgets('installed shows delete', (tester) async {
    await tester.pumpWidget(build(const LocalGameState(
        status: InstallStatus.installed, updateAvailable: false,
        missing: [], presentPaths: ['/roms/snes/m.sfc'])));
    await tester.pumpAndSettle();
    expect(find.text('Usuń z urządzenia'), findsOneWidget);
  });
}
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja** — wg Interfaces. Usuwanie:

```dart
Future<void> deleteLocalFiles(List<String> presentPaths) async {
  for (final path in presentPaths) {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
```

(żadnych `Directory.delete(recursive: true)` — Global Constraint).

- [ ] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: download, delete and install badges on game screens"`

---

### Task 7: Ekran „Pobierania"

**Files:**
- Create: `app/lib/features/downloads/downloads_screen.dart`
- Modify: `app/lib/app/router.dart` (trasa `/downloads` + ikona w AppBar biblioteki z licznikiem aktywnych)
- Test: `app/test/features/downloads_screen_test.dart`

**Interfaces:**
- Produces: `DownloadsScreen` — sekcja „Aktywne" (nazwa gry, pasek postępu, przyciski pauza/wznów/anuluj z `DownloadManager`) i „Historia" (ukończone/błędne z `FileDownloader().database.allRecords()`, błędne z przyciskiem „Ponów" → `retryGame`). Provider `activeDownloadsProvider` eksponujący listę `GameProgress {gameId, title, progress, status}`.

- [ ] **Step 1: Failing test** — widget test: przy nadpisanym `activeDownloadsProvider` z jednym wpisem (progress 0.5) ekran pokazuje tytuł gry i `LinearProgressIndicator`; przy pustym — tekst „Brak aktywnych pobierań".

```dart
import 'package:droplet/features/downloads/downloads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty state', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [activeDownloadsProvider.overrideWith((ref) => const [])],
      child: const MaterialApp(home: DownloadsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Brak aktywnych pobierań'), findsOneWidget);
  });

  testWidgets('active download row', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeDownloadsProvider.overrideWith((ref) => const [
              GameProgress(gameId: 7, title: 'Mario', progress: 0.5,
                  status: GameProgressStatus.running),
            ])
      ],
      child: const MaterialApp(home: DownloadsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mario'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
```

- [ ] **Step 2: FAIL**, **Step 3: Implementacja** wg Interfaces, **Step 4: PASS**.

- [ ] **Step 5: Commit** — `git commit -m "feat: downloads screen with queue and history"`

---

### Task 8: E2E pobierania (integration_test)

**Files:**
- Create: `app/integration_test/download_flow_test.dart`

**Interfaces:**
- Consumes: harness `scripts/e2e_app.sh` z M4 (backend e2e + fixture-library), ekrany i manager z Tasków 1–7.

- [ ] **Step 1: Napisz test e2e**

Najpierw `flutter pub add path_provider` (używany niżej; M6 też z niego korzysta).

`app/integration_test/download_flow_test.dart` (ta sama konwencja co `app_flow_test.dart`: `E2E_SERVER` z dart-define, seed skanem w `setUpAll`):

```dart
import 'dart:io';

import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const server = String.fromEnvironment('E2E_SERVER');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final client = ApiClient(baseUrl: server);
    final token = await client.login('e2e', 'e2e-pass-123');
    await ApiClient(baseUrl: server, token: token).triggerScan();
    await Future<void>.delayed(const Duration(seconds: 5));
  });

  testWidgets('download then delete a game', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DropletApp()));
    await tester.pumpAndSettle();

    // logowanie (pomijane, jeśli sesja została z poprzedniego testu)
    if (tester.any(find.text('Zaloguj'))) {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), server);
      await tester.enterText(fields.at(1), 'e2e');
      await tester.enterText(fields.at(2), 'e2e-pass-123');
      await tester.tap(find.text('Zaloguj'));
      await tester.pumpAndSettle(const Duration(seconds: 10));
    }

    // w e2e katalog bazowy = katalog aplikacji (bez MANAGE_EXTERNAL_STORAGE,
    // którego nie da się kliknąć z testu) — ustaw przez ustawienia
    final baseDir = '${(await getApplicationDocumentsDirectory()).path}/roms';
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('base-dir-field')), baseDir);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // pobierz Super Mario World
    await tester.tap(find.text('Super Mario World'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pobierz'));
    // czekaj na status "zainstalowana" (max 60 s)
    var installed = false;
    for (var i = 0; i < 60 && !installed; i++) {
      await tester.pump(const Duration(seconds: 1));
      installed = tester.any(find.textContaining('Zainstalowana'));
    }
    expect(installed, true);
    final romFile = File('$baseDir/snes/Super Mario World (USA).sfc');
    expect(romFile.existsSync(), true);
    expect(romFile.lengthSync(), 4); // rozmiar z fixture-library

    // usuń
    await tester.tap(find.text('Usuń z urządzenia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń')); // potwierdzenie w dialogu
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(romFile.existsSync(), false);
    expect(find.textContaining('Pobierz'), findsOneWidget);
  });
}
```

Wymaga: pola katalogu bazowego w ustawieniach z `Key('base-dir-field')` (dodaj w Task 2, jeśli brakuje) i przycisku potwierdzenia „Usuń" w dialogu (Task 6).

- [ ] **Step 2: Uruchom** — `E2E_SERVER=http://<ip-hosta>:8800 ./scripts/e2e_app.sh` na podłączonym urządzeniu → oba pliki integration_test PASS.

- [ ] **Step 3: Commit** — `git add app/integration_test && git commit -m "test: download and delete e2e flow"`

---

### Task 9: Checklista ręczna na realnym NAS (kryteria M5)

Automatyczne e2e nie pokryją integracji z RetroArchem, dużych plików i zrywania sieci — to zostaje ręczne.

**Files:**
- Create: `docs/testing-m5.md` (checklista + wyniki)

- [ ] **Step 0: Bramki automatyczne** — `flutter test` + `./scripts/check_coverage_app.sh` (100%) + `./scripts/e2e_app.sh` (PASS) + `./scripts/e2e_backend.sh` (PASS).

- [ ] **Step 1: Przejdź checklistę na fizycznym telefonie + realnym NAS:**

1. Mała gra (kartridż): Pobierz → ląduje w `<base>/<system>/`, badge „zainstalowana", RetroArch ją widzi i uruchamia.
2. Duża gra (kilka GB, obraz płyty): start pobierania → pauza → wznowienie → wyłączenie Wi-Fi w trakcie → powrót sieci → retry/wznowienie → plik kompletny (rozmiar zgodny z manifestem).
3. Gra wieloplikowa (cue/bin lub multi-disc): wszystkie pliki pobrane, jedna pozycja na ekranie pobierań.
4. Switch: domyślna selekcja = base + najnowszy update + DLC; po pobraniu tylko base — badge „dostępna aktualizacja".
5. Usunięcie gry: pliki ROM znikają, katalog `saves/`/`states/` RetroArcha nietknięty (sprawdź ręcznie), badge wraca do „niezainstalowana".
6. Zabicie aplikacji w trakcie pobierania → pobieranie kontynuuje w tle (powiadomienie), po powrocie stan poprawny.

- [ ] **Step 2: Wyniki do `docs/testing-m5.md`** — każdy punkt: PASS/FAIL + notatka; FAIL-e naprawione przed zamknięciem milestone'u.

- [ ] **Step 3: Commit** — `git add docs/testing-m5.md && git commit -m "docs: M5 device e2e results"`
