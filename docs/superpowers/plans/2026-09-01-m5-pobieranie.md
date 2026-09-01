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
- Pluginy (permission_handler, background_downloader) są schowane za interfejsami-portami w `lib/core/platform/` (`PermissionsPort`, `DownloaderPort`). Implementacje na pluginie to jedyne pliki z `// coverage:ignore-file` (lista zamknięta w M4 Global Constraints); cała logika (`DownloadManager`, `ensureStoragePermission`, diff, selekcja) chodzi na portach i jest testowana na fake'ach do 100%.
- `const kE2E = bool.fromEnvironment('E2E')` (`lib/core/env.dart`): w biegu e2e aplikacja nie pokazuje systemowych dialogów uprawnień (test integracyjny nie umie ich kliknąć). Jedyne użycie tej flagi: pominięcie promptu o powiadomieniach.
- Nawigacja do `/downloads` — trasa zagnieżdżona pod `/` (jak w M4).

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
// providers: storageSettingsRepositoryProvider = Provider<StorageSettingsRepository>
//            storageSettingsProvider = FutureProvider<StorageSettings>
```

- [x] **Step 1: Failing testy**

`app/test/core/storage_settings_test.dart`:

```dart
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

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

  group('repository', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('defaults when empty', () async {
      final s = await StorageSettingsRepository(SharedPreferencesAsync()).load();
      expect(s.baseDir, '/storage/emulated/0/RetroArch/roms');
      expect(s.systemDirs, isEmpty);
    });

    test('persists base dir and system dirs', () async {
      final repo = StorageSettingsRepository(SharedPreferencesAsync());
      await repo.saveBaseDir('/sdcard/roms');
      await repo.saveSystemDir('psx', 'PlayStation');
      await repo.saveSystemDir('snes', 'SNES');
      final s = await repo.load();
      expect(s.baseDir, '/sdcard/roms');
      expect(s.systemDirs, {'psx': 'PlayStation', 'snes': 'SNES'});
    });
  });
}
```

- [x] **Step 2: FAIL** — `flutter test test/core/storage_settings_test.dart`

- [x] **Step 3: Implementacja** — czysta klasa + repozytorium na `SharedPreferencesAsync` (klucze `storage.base_dir`, `storage.system_dirs` jako JSON). Provider'y w tym samym pliku (`storageSettingsProvider` czyta `storageSettingsRepositoryProvider`). `shared_preferences_platform_interface` jest zależnością tranzytywną — dodaj jawnie do `dev_dependencies` (`flutter pub add --dev shared_preferences_platform_interface`).

- [x] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: storage settings with per-system directories"`

---

### Task 2: Uprawnienia + sekcja „Pobieranie" w ustawieniach

**Files:**
- Create: `app/lib/core/platform/permissions_port.dart`, `app/lib/core/downloads/permissions.dart`, `app/lib/core/env.dart`
- Modify: `app/lib/features/settings/settings_screen.dart`, `app/android/app/src/main/AndroidManifest.xml`
- Test: `app/test/core/permissions_test.dart`, `app/test/features/settings_downloads_test.dart`

**Interfaces:**
- Produces:

```dart
// lib/core/env.dart
const kE2E = bool.fromEnvironment('E2E');

// lib/core/platform/permissions_port.dart  (// coverage:ignore-file — cienki adapter pluginu)
abstract class PermissionsPort {
  Future<bool> hasAllFilesAccess();       // Permission.manageExternalStorage.isGranted
  Future<bool> requestAllFilesAccess();   // .request(); odmowa -> openAppSettings(); zwraca isGranted po powrocie
  Future<List<String>> appPrivateDirs();  // [getApplicationDocumentsDirectory().path, getExternalStorageDirectory()?.path]
}
class PermissionHandlerPort implements PermissionsPort { ... }
final permissionsPortProvider = Provider<PermissionsPort>((_) => PermissionHandlerPort());

// lib/core/downloads/permissions.dart  (czysta logika, 100%)
bool needsAllFilesAccess(String baseDir, List<String> appPrivateDirs);
//   false, gdy baseDir leży w katalogu prywatnym aplikacji (zapis działa bez uprawnienia — z tego korzysta e2e)
Future<bool> ensureStoragePermission(PermissionsPort port, String baseDir);
//   !needsAllFilesAccess -> true; hasAllFilesAccess -> true; inaczej requestAllFilesAccess()
```

- Sekcja **Pobieranie** w ustawieniach: pole katalogu bazowego `Key('base-dir-field')` zapisywane **`onChanged`** przez `saveBaseDir` (e2e wpisuje ścieżkę i od razu wychodzi z ekranu), lista systemów z edycją podkatalogu (`Key('system-dir-<code>')`), status uprawnienia („Przyznane" / „Brak") z przyciskiem „Przyznaj" (`Key('grant-permission')`).

- [x] **Step 1: Failing testy**

`app/test/core/permissions_test.dart`:

```dart
import 'package:droplet/core/downloads/permissions.dart';
import 'package:droplet/core/platform/permissions_port.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePermissionsPort implements PermissionsPort {
  FakePermissionsPort({required this.granted, this.grantOnRequest = false});
  bool granted;
  final bool grantOnRequest;
  int requests = 0;

  @override
  Future<bool> hasAllFilesAccess() async => granted;

  @override
  Future<bool> requestAllFilesAccess() async {
    requests++;
    if (grantOnRequest) granted = true;
    return granted;
  }

  @override
  Future<List<String>> appPrivateDirs() async =>
      ['/data/user/0/dev.johniak.droplet/app_flutter'];
}

void main() {
  const appDirs = ['/data/user/0/dev.johniak.droplet/app_flutter'];

  test('app-private dir needs no permission, shared storage does', () {
    expect(needsAllFilesAccess('${appDirs.first}/roms', appDirs), false);
    expect(needsAllFilesAccess('/storage/emulated/0/RetroArch/roms', appDirs), true);
  });

  test('skips request for app-private base dir', () async {
    final port = FakePermissionsPort(granted: false);
    expect(await ensureStoragePermission(port, '${appDirs.first}/roms'), true);
    expect(port.requests, 0);
  });

  test('requests when missing and returns result', () async {
    final ok = FakePermissionsPort(granted: false, grantOnRequest: true);
    expect(await ensureStoragePermission(ok, '/storage/emulated/0/roms'), true);
    expect(ok.requests, 1);
    final denied = FakePermissionsPort(granted: false);
    expect(await ensureStoragePermission(denied, '/storage/emulated/0/roms'), false);
  });

  test('already granted -> no request', () async {
    final port = FakePermissionsPort(granted: true);
    expect(await ensureStoragePermission(port, '/storage/emulated/0/roms'), true);
    expect(port.requests, 0);
  });
}
```

`app/test/features/settings_downloads_test.dart` (fake porty jak wyżej — wynieś `FakePermissionsPort` do `test/fakes/fake_permissions_port.dart`, żeby oba testy go współdzieliły):

```dart
testWidgets('download section edits base dir and shows permission', (tester) async {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  final repo = StorageSettingsRepository(SharedPreferencesAsync());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sessionProvider.overrideWith(() => _FakeSession()),   // jak w M4 Task 8
      storageSettingsRepositoryProvider.overrideWithValue(repo),
      permissionsPortProvider.overrideWithValue(FakePermissionsPort(granted: true)),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Pobieranie'), findsOneWidget);
  expect(find.text('Przyznane'), findsOneWidget);
  await tester.enterText(find.byKey(const Key('base-dir-field')), '/tmp/roms');
  await tester.pumpAndSettle();
  expect((await repo.load()).baseDir, '/tmp/roms');
});

testWidgets('grant button requests permission', (tester) async {
  final port = FakePermissionsPort(granted: false, grantOnRequest: true);
  // ...te same overrides z `port`...
  await tester.tap(find.byKey(const Key('grant-permission')));
  await tester.pumpAndSettle();
  expect(port.requests, 1);
  expect(find.text('Przyznane'), findsOneWidget);
});
```

- [x] **Step 2: FAIL**

- [x] **Step 3: Implementacja** — wg Interfaces; do manifestu dwa `uses-permission` z Global Constraints. `permissions_port.dart` zaczyna się od `// coverage:ignore-file`.

- [x] **Step 4: PASS** (testy i bramka 100%; sprawdzenie na telefonie odlozone na czlowieka)

Oryginalny krok: — `flutter test` + `./scripts/check_coverage_app.sh`; ręcznie na telefonie: przyznanie uprawnienia przechodzi przez systemowy ekran i wraca ze statusem „Przyznane"; utworzenie katalogu bazowego działa.

- [x] **Step 5: Commit** — `git commit -m "feat: storage permission flow and download settings section"`

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

- [x] **Step 1: Failing testy**

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

- [x] **Step 2: FAIL**

- [x] **Step 3: Implementacja**

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

- [x] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: default file selection with newest-update rule"`

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

  group('scanSystemDir', () {
    test('missing dir -> empty map', () async {
      expect(await scanSystemDir('/nie/ma/takiego'), isEmpty);
    });

    test('maps basenames to sizes, skips subdirectories', () async {
      final dir = await Directory.systemTemp.createTemp();
      File('${dir.path}/a.sfc').writeAsBytesSync(List.filled(3, 0));
      File('${dir.path}/b.sfc').writeAsBytesSync(List.filled(5, 0));
      Directory('${dir.path}/sub').createSync();
      expect(await scanSystemDir(dir.path), {'a.sfc': 3, 'b.sfc': 5});
    });
  });
}
```

(`import 'dart:io';` + `import 'package:droplet/core/downloads/local_scanner.dart';` na górze.)

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja** — `diffGame` wg reguł (korzysta z `defaultSelection` i `settings.pathFor`); `scanSystemDir` przez `Directory(dirPath).list()` → mapa `basename -> length` (tylko `File`, katalogi pomijane; brak katalogu → `{}`).

- [ ] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: manifest-to-disk diff with install status"`

---

### Task 5: Download manager

**Files:**
- Create: `app/lib/core/platform/downloader_port.dart`, `app/lib/core/downloads/download_manager.dart`, `app/lib/core/downloads/task_builder.dart`, `app/test/fakes/fake_downloader_port.dart`
- Modify: `app/lib/main.dart` (konfiguracja powiadomień przy starcie)
- Test: `app/test/core/task_builder_test.dart`, `app/test/core/download_manager_test.dart`

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
// baseDirectory: BaseDirectory.root, directory: settings.dirFor(systemCode) (ścieżka
//   ABSOLUTNA, z wiodącym '/' — tak dokumentuje to background_downloader dla root),
// filename: file.name, group: 'game-$gameId', allowPause: true, retries: 3,
// updates: Updates.statusAndProgress, metaData: '{"gameId":$gameId,"size":${file.size}}'
int gameIdOf(Task task);  int expectedSizeOf(Task task);   // z metaData
```

  - `lib/core/platform/downloader_port.dart` (`// coverage:ignore-file` — adapter na `FileDownloader()`):

```dart
abstract class DownloaderPort {
  Stream<TaskUpdate> get updates;                 // FileDownloader().updates
  Future<bool> enqueue(DownloadTask task);
  Future<bool> pause(DownloadTask task);
  Future<bool> resume(DownloadTask task);
  Future<bool> cancel(String taskId);             // cancelTaskWithId
  Future<List<TaskRecord>> allRecords();          // database.allRecords()
  Future<List<TaskRecord>> recordsForGroup(String group);
  Future<String> filePath(Task task);             // task.filePath()
  Future<int?> fileLength(String path);           // File(path).length(), null gdy brak
  Future<void> deleteFile(String path);
  Future<void> ensureNotificationPermission();    // permissions.request(PermissionType.notifications)
}
class BackgroundDownloaderPort implements DownloaderPort { ... }
final downloaderPortProvider = Provider<DownloaderPort>((_) => BackgroundDownloaderPort());
```

  - `download_manager.dart` — `DownloadManager` (provider `downloadManagerProvider`, konstruktor `DownloadManager(DownloaderPort port, PermissionsPort permissions, {required void Function(int gameId) onGameChanged})`):
    - `Future<void> downloadGame({required GameDetail game, required Set<int> selectedIds, required LocalGameState local, required String serverUrl, required Map<String, String> authHeaders, required StorageSettings settings})` — `ensureStoragePermission` (rzuca `PermissionDeniedException` przy odmowie), `ensureNotificationPermission()` (pomijane gdy `kE2E`), enqueue tasków dla zaznaczonych plików **z pominięciem już obecnych** (`local.presentPaths`),
    - nasłuch `port.updates`: `TaskProgressUpdate` → aktualizacja postępu gry (średnia ważona `expectedSizeOf`); `TaskStatusUpdate.complete` → `fileLength(filePath)` vs `expectedSizeOf` — niezgodność: `deleteFile` + status `failed`; po każdym zakończeniu `onGameChanged(gameId)` (feature podpina `ref.invalidate(localStateProvider(gameId))`),
    - `pauseGame/resumeGame/cancelGame/retryGame(int gameId)` (po `recordsForGroup('game-$gameId')`),
    - `Map<int, GameProgress> get progress` + `Stream<Map<int, GameProgress>> get progressStream`; `GameProgress {gameId, title, progress, status: GameProgressStatus running|paused|failed|complete}`.
  - W `main.dart` (wewnątrz `main()` — ignorowane w pokryciu): `FileDownloader().configureNotification(running:, complete:, error:, progressBar: true)`.

- [ ] **Step 1: Failing testy**

`app/test/core/task_builder_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/downloads/task_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const file = GameFileModel(id: 42, name: 'Mario (USA).sfc',
      relativePath: 'snes/Mario (USA).sfc', role: FileRole.base,
      discNumber: null, version: '', size: 1024);

  test('buildTask fills url, path, group and headers', () {
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
    expect(task.directory, '/storage/emulated/0/RetroArch/roms/snes');
    expect(task.filename, 'Mario (USA).sfc');
    expect(task.group, 'game-7');
    expect(task.allowPause, true);
    expect(gameIdOf(task), 7);
    expect(expectedSizeOf(task), 1024);
  });
}
```

`app/test/fakes/fake_downloader_port.dart`:

```dart
import 'dart:async';
import 'package:background_downloader/background_downloader.dart';
import 'package:droplet/core/platform/downloader_port.dart';

class FakeDownloaderPort implements DownloaderPort {
  final controller = StreamController<TaskUpdate>.broadcast();
  final enqueued = <DownloadTask>[];
  final deleted = <String>[];
  final lengths = <String, int?>{};      // ścieżka -> rozmiar (null = brak pliku)
  int notificationRequests = 0;
  final paused = <String>[], resumed = <String>[], cancelled = <String>[];

  @override Stream<TaskUpdate> get updates => controller.stream;
  @override Future<bool> enqueue(DownloadTask task) async { enqueued.add(task); return true; }
  @override Future<bool> pause(DownloadTask task) async { paused.add(task.taskId); return true; }
  @override Future<bool> resume(DownloadTask task) async { resumed.add(task.taskId); return true; }
  @override Future<bool> cancel(String taskId) async { cancelled.add(taskId); return true; }
  @override Future<List<TaskRecord>> allRecords() async => [];
  @override Future<List<TaskRecord>> recordsForGroup(String group) async =>
      [for (final t in enqueued.where((t) => t.group == group))
        TaskRecord(t, TaskStatus.running, 0.5, 1024)];
  @override Future<String> filePath(Task task) async => '${task.directory}/${task.filename}';
  @override Future<int?> fileLength(String path) async => lengths[path];
  @override Future<void> deleteFile(String path) async => deleted.add(path);
  @override Future<void> ensureNotificationPermission() async => notificationRequests++;
}
```

`app/test/core/download_manager_test.dart`:

```dart
void main() {
  const file = GameFileModel(id: 42, name: 'm.sfc', relativePath: 'snes/m.sfc',
      role: FileRole.base, discNumber: null, version: '', size: 1024);
  const game = GameDetail(id: 7, title: 'Mario', systemCode: 'snes', systemName: 'SNES',
      hasCover: false, totalSize: 1024, files: [file]);
  final settings = StorageSettings('/roms', {});
  const none = LocalGameState(status: InstallStatus.none, updateAvailable: false,
      missing: [file], presentPaths: []);

  late FakeDownloaderPort port;
  late FakePermissionsPort perms;
  late List<int> changed;
  late DownloadManager manager;

  setUp(() {
    port = FakeDownloaderPort();
    perms = FakePermissionsPort(granted: true);
    changed = [];
    manager = DownloadManager(port, perms, onGameChanged: changed.add);
  });

  Future<void> start([LocalGameState local = none]) => manager.downloadGame(
      game: game, selectedIds: {42}, local: local, serverUrl: 'http://nas:8000',
      authHeaders: const {'Authorization': 'Token t'}, settings: settings);

  test('enqueues selected, missing files', () async {
    await start();
    expect(port.enqueued.single.url, 'http://nas:8000/api/files/42/download');
    expect(manager.progress[7]?.status, GameProgressStatus.running);
  });

  test('skips files already present', () async {
    await start(const LocalGameState(status: InstallStatus.installed,
        updateAvailable: false, missing: [], presentPaths: ['/roms/snes/m.sfc']));
    expect(port.enqueued, isEmpty);
  });

  test('denied permission throws and enqueues nothing', () async {
    perms.granted = false;
    manager = DownloadManager(port, perms, onGameChanged: changed.add);
    await expectLater(start(), throwsA(isA<PermissionDeniedException>()));
    expect(port.enqueued, isEmpty);
  });

  test('progress updates are size-weighted', () async {
    await start();
    port.controller.add(TaskProgressUpdate(port.enqueued.single, 0.25));
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[7]?.progress, closeTo(0.25, 0.001));
  });

  test('complete with matching size -> complete + onGameChanged', () async {
    await start();
    port.lengths['/roms/snes/m.sfc'] = 1024;
    port.controller.add(TaskStatusUpdate(port.enqueued.single, TaskStatus.complete));
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[7]?.status, GameProgressStatus.complete);
    expect(changed, [7]);
    expect(port.deleted, isEmpty);
  });

  test('complete with size mismatch -> file deleted, failed', () async {
    await start();
    port.lengths['/roms/snes/m.sfc'] = 10;
    port.controller.add(TaskStatusUpdate(port.enqueued.single, TaskStatus.complete));
    await Future<void>.delayed(Duration.zero);
    expect(port.deleted, ['/roms/snes/m.sfc']);
    expect(manager.progress[7]?.status, GameProgressStatus.failed);
  });

  test('failed/paused statuses map to progress status', () async {
    await start();
    port.controller.add(TaskStatusUpdate(port.enqueued.single, TaskStatus.paused));
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[7]?.status, GameProgressStatus.paused);
    port.controller.add(TaskStatusUpdate(port.enqueued.single, TaskStatus.failed));
    await Future<void>.delayed(Duration.zero);
    expect(manager.progress[7]?.status, GameProgressStatus.failed);
  });

  test('pause/resume/cancel/retry act on the game group', () async {
    await start();
    await manager.pauseGame(7);
    await manager.resumeGame(7);
    await manager.cancelGame(7);
    expect(port.paused.length + port.resumed.length + port.cancelled.length, 3);
    await manager.retryGame(7);
    expect(port.enqueued.length, 2);
  });

  test('notification permission requested once (not in e2e)', () async {
    await start();
    await start();
    expect(port.notificationRequests, kE2E ? 0 : 1);
  });
}
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja** — `task_builder.dart`, `downloader_port.dart` (adapter, `// coverage:ignore-file`), `download_manager.dart` wg Interfaces. `downloadManagerProvider` tworzy managera z `downloaderPortProvider`, `permissionsPortProvider` i `onGameChanged: (id) => ref.invalidate(localStateProvider(id))` (provider z Task 6 — w tym tasku callback tymczasowo pusty, Task 6 podpina).

- [ ] **Step 4: PASS** — `flutter test` + `./scripts/check_coverage_app.sh`; build na telefon i szybki test ręczny małego pliku.

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

  testWidgets('update available shows update button', (tester) async {
    await tester.pumpWidget(build(const LocalGameState(
        status: InstallStatus.partial, updateAvailable: true,
        missing: [], presentPaths: ['/roms/snes/m.sfc'])));
    await tester.pumpAndSettle();
    expect(find.text('Pobierz aktualizację'), findsOneWidget);
  });

  testWidgets('delete dialog removes only listed files', (tester) async {
    final dir = await Directory.systemTemp.createTemp();
    final rom = File('${dir.path}/m.sfc')..writeAsStringSync('rom');
    final save = File('${dir.path}/m.srm')..writeAsStringSync('save');  // „save" obok ROM-a
    await tester.pumpWidget(build(LocalGameState(
        status: InstallStatus.installed, updateAvailable: false,
        missing: const [], presentPaths: [rom.path])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń z urządzenia'));
    await tester.pumpAndSettle();
    expect(find.textContaining('nie zostaną usunięte'), findsOneWidget);
    await tester.tap(find.text('Usuń'));
    await tester.pumpAndSettle();
    expect(rom.existsSync(), false);
    expect(save.existsSync(), true);
  });

  test('deleteLocalFiles ignores missing paths', () async {
    final dir = await Directory.systemTemp.createTemp();
    await deleteLocalFiles(['${dir.path}/nie-ma.sfc']);  // nie rzuca
  });
}
```

(`import 'dart:io';` + import `delete_dialog.dart`.)

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja** — wg Interfaces. Usuwanie (w `delete_dialog.dart`):

```dart
Future<void> deleteLocalFiles(List<String> presentPaths) async {
  for (final path in presentPaths) {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
```

(żadnych `Directory.delete(recursive: true)` — Global Constraint). Przycisk „Pobierz" woła `downloadManagerProvider.downloadGame(...)`; `PermissionDeniedException` → `SnackBar` „Bez dostępu do plików nie pobiorę ROM-ów — przyznaj uprawnienie w ustawieniach". W tym tasku podepnij też `onGameChanged` managera pod `ref.invalidate(localStateProvider(gameId))`.

- [ ] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: download, delete and install badges on game screens"`

---

### Task 7: Ekran „Pobierania"

**Files:**
- Create: `app/lib/features/downloads/downloads_screen.dart`
- Modify: `app/lib/app/router.dart` (trasa `/downloads` + ikona w AppBar biblioteki z licznikiem aktywnych)
- Test: `app/test/features/downloads_screen_test.dart`

**Interfaces:**
- Produces: `DownloadsScreen` — sekcja „Aktywne" (nazwa gry, pasek postępu, przyciski pauza/wznów/anuluj z `DownloadManager`) i „Historia" (ukończone/błędne z `FileDownloader().database.allRecords()`, błędne z przyciskiem „Ponów" → `retryGame`). Provider `activeDownloadsProvider` eksponujący listę `GameProgress {gameId, title, progress, status}`.

- [ ] **Step 1: Failing test** — widget test: przy nadpisanym `activeDownloadsProvider` z jednym wpisem (progress 0.5) ekran pokazuje tytuł gry i `LinearProgressIndicator`; przy pustym — tekst „Brak aktywnych pobierań". Dodaj też przypadki: wpis `failed` pokazuje „Ponów", a tapnięcie pauzy/ponów woła metody managera (nadpisz `downloadManagerProvider` managerem na `FakeDownloaderPort` z Task 5 i sprawdź `port.paused`/`port.enqueued`) — każdy przycisk musi mieć test, inaczej jego handler jest nieprzykryty.

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
    await const FlutterSecureStorage().deleteAll();  // czysty start jak w app_flow_test
    final client = ApiClient(baseUrl: server);
    final token = await client.login('e2e', 'e2e-pass-123');
    await ApiClient(baseUrl: server, token: token).triggerScan();
    await Future<void>.delayed(const Duration(seconds: 5));
  });

  testWidgets('download then delete a game', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DropletApp()));
    await tester.pumpAndSettle();

    // logowanie
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), server);
    await tester.enterText(fields.at(1), 'e2e');
    await tester.enterText(fields.at(2), 'e2e-pass-123');
    await tester.tap(find.text('Zaloguj'));
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // w e2e katalog bazowy = katalog prywatny aplikacji: `needsAllFilesAccess`
    // zwraca false, więc aplikacja NIE prosi o MANAGE_EXTERNAL_STORAGE (dialogu
    // systemowego nie da się kliknąć z testu), a --dart-define=E2E=true pomija
    // prompt o powiadomieniach
    final baseDir = '${(await getApplicationDocumentsDirectory()).path}/roms';
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('base-dir-field')), baseDir);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // pobierz Super Mario World (tytuł może być 2x: placeholder + podpis)
    await tester.tap(find.text('Super Mario World').first);
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

Wymaga: pola katalogu bazowego w ustawieniach z `Key('base-dir-field')` zapisywanego `onChanged` (Task 2), przycisku potwierdzenia „Usuń" w dialogu (Task 6) oraz `--dart-define=E2E=true` w `scripts/e2e_app.sh` (M4 Task 9). Import `flutter_secure_storage` w teście.

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
