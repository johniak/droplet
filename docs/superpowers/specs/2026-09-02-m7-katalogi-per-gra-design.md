# M7 — katalog per gra i skan urządzenia

Data: 2026-09-02. Dotyczy backendu (`backend/`) i aplikacji (`app/`). Bazuje na stanie
po redesignie Glass (commit `e02d467` na `main`).

## 1. Po co

Gry mają wiele plików (Switch: base + aktualizacje + DLC; PSX: cue + bin per płyta;
mody). Dziś skaner grupuje pliki po nazwie ignorując foldery, a aplikacja zapisuje
wszystko płasko do `<roms>/<system>/`, co robi śmietnik. Do tego stan „zainstalowana"
liczony jest per kafel (osobne zapytanie o szczegół gry i skan katalogu), więc filtry
i półka „Na urządzeniu" znają tylko gry, których kafel zdążył się wyrenderować.

Cel: **jedna gra = jeden katalog** po obu stronach oraz **jeden skan urządzenia**
oparty o manifest całej biblioteki, z którego wynika stan każdej gry bez zapytań per
gra.

## 2. Decyzje

| Temat | Decyzja |
|---|---|
| Reguła grupowania na serwerze | Podkatalog bezpośrednio pod katalogiem systemu = jedna gra. Wszystkie pliki w nim (rekurencyjnie) należą do niej. |
| Pliki luzem w katalogu systemu | Nie trafiają do biblioteki. Zapisywane jako `LooseFile`, widoczne w adminie jako „do uporządkowania". |
| Tytuł gry | Z nazwy katalogu (`display_title` / `normalize_title` jak dziś dla nazw plików). |
| Tożsamość gry | `Game.folder` = ścieżka względna katalogu (`system/Folder`), unikalna. Zastępuje `UniqueConstraint(system, normalized_title)`. |
| Kontrakt API | Dochodzi `folder` w liście i szczególe gry oraz nowy `GET /api/manifest/`. Reszta bez zmian. |
| Ścieżka na telefonie | `<roms>/<system>/<folder>/<plik>` (folder = nazwa katalogu z serwera). |
| Stan lokalny | Jeden skan urządzenia + manifest → mapa `gameId → LocalGameState`; odznaki, filtry, półka i karta gry czytają z mapy. |
| Pliki pobrane wcześniej płasko | Bez migracji. Widoczne w Ustawieniach jako „Nieznane na urządzeniu" z opcją usunięcia. |
| Skan urządzenia | Synchroniczne `dart:io` (jak dotąd; async nie kończy się w widget testach). Gdy na urządzeniu przekroczy ~1 s dla realnej biblioteki, przenieść do `compute()` — poza zakresem M7. |
| Wersja aplikacji | `0.3.0+3` |

## 3. Backend

### 3.1 Model

```python
class Game(models.Model):
    system = FK(System)
    folder = CharField(max_length=1000, unique=True)   # "snes/Super Mario World (USA)"
    title = CharField(500)
    normalized_title = CharField(500, db_index=True)   # dalej używane przez okładki i szukajkę
    switch_title_prefix = CharField(12, blank=True, db_index=True)
    created_at = DateTimeField(auto_now_add=True)
    # bez UniqueConstraint(system, normalized_title)

class LooseFile(models.Model):
    system = FK(System, related_name="loose_files")
    relative_path = CharField(1000, unique=True)
    size = BigIntegerField()

class ScanRun:  # + pole
    loose_files = IntegerField(default=0)
```

Migracja: dodaje `folder` (domyślnie `""`), usuwa stary constraint, dodaje `LooseFile`
i `ScanRun.loose_files`; drugi krok migracji ustawia `folder` dla istniejących gier
z pierwszego pliku (`dirname(relative_path)`), a gry, których pliki leżą luzem
(`dirname == system_dir`), dostają `folder = ""` i zostaną usunięte przez pierwszy skan
(brak plików). Unikalność `folder` włączana dopiero po wypełnieniu.

### 3.2 Skaner (`library/scanner/grouping.py`)

`group_system_dir(system_dir, library_root, *, is_switch) -> tuple[list[GameGroup], list[LooseEntry]]`

- Iteruje `system_dir.iterdir()` (posortowane). Katalogi ukryte (`.`) pomijane.
- Każdy podkatalog → `GameGroup(folder=relative(system_dir/sub), title=display_title(sub.name), normalized_title=normalize_title(sub.name))`. Pliki: `sub.rglob("*")` bez ukrytych.
  Role wewnątrz katalogu:
  1. `.m3u` → jak dziś: m3u `support`, płyty `disc` z numerem, `.bin` z cue `support`.
  2. samodzielne `.cue` → `base` + `.bin` `support`.
  3. Switch: `parse_switch(stem)` → `base` / `update` / `dlc` z wersją; `switch_title_prefix` grupy = prefiks title-id pliku `base` (jeśli jest).
  4. Pozostałe pliki: rozszerzenie z listy `SIDECAR_EXTENSIONS = {".txt", ".nfo", ".md", ".jpg", ".jpeg", ".png", ".pdf", ".sav", ".srm", ".state", ".xml", ".json"}` → `other`; reszta → `base`.
- Pliki bezpośrednio w `system_dir` → `LooseEntry(relative_path, size)`.
- `GameGroup` dostaje pole `folder: str`.

### 3.3 Synchronizacja (`library/scanner/scan.py`)

- `_find_game(system, group)` → `Game.objects.filter(folder=group.folder).first()`.
- Zmiana nazwy katalogu = nowa gra + usunięcie starej (pliki znikają). Świadomie proste.
- Aktualizacja tytułu: jeśli `game.title != group.title` (zmiana nazwy pliku w środku nie zmienia tytułu; tylko zmiana nazwy katalogu, która i tak tworzy nową grę) — bez zmian tytułu po utworzeniu.
- `LooseFile`: po przejściu wszystkich systemów zbiór zastępowany: usuń wpisy, których nie ma w tym skanie, dodaj nowe, zaktualizuj rozmiar. `run.loose_files = len(all_loose)`.
- Usuwanie nieaktualnych `GameFile` i pustych `Game` jak dziś.

### 3.4 Admin

- `LooseFileAdmin`: `list_display = ["relative_path", "system", "size"]`, `list_filter = ["system"]`, `search_fields = ["relative_path"]`, tylko do odczytu.
- `SystemAdmin.list_display` + kolumna `loose_count` („luzem").
- `ScanRunAdmin` (jeśli istnieje) pokazuje `loose_files`.

### 3.5 API

- `GameListSerializer` i `GameDetailSerializer` + pole `folder` = ostatni segment `Game.folder` (nazwa katalogu bez systemu).
- Nowy `GET /api/manifest/` (token, bez paginacji), `ordering = ["id"]`:

```json
[
  {"id": 7, "system_code": "switch", "folder": "Hollow Knight",
   "files": [{"id": 1, "name": "Hollow Knight [0100633007D48000][v0].nsp",
              "role": "base", "version": "", "disc_number": null, "size": 123}]}
]
```

`name` = ostatni segment `relative_path`. Dla plików w podkatalogach gry (np. `disc1/…`)
`name` zawiera ścieżkę względem katalogu gry (`disc1/x.bin`) — aplikacja odtwarza ją
pod katalogiem gry. Ta sama reguła obowiązuje w `GameDetailSerializer.files[].name`
(dziś to sam basename; zmiana zgodna wstecz dla płaskich katalogów).

### 3.6 Okładki

Bez zmian: dopasowanie po `normalized_title`, które teraz pochodzi z nazwy katalogu.

### 3.7 Fixture e2e

```
snes/Super Mario World (USA)/Super Mario World (USA).sfc
snes/Luzem (USA).sfc                         ← LooseFile
psx/Tekken (USA)/Tekken (USA).cue + .bin
switch/Hollow Knight/Hollow Knight [0100633007D48000][v0].nsp
switch/Hollow Knight/Hollow Knight [UPD][0100633007D48800][v196608].nsp
Dziwny Folder/tajemniczy.rom                 ← system needs_config, plik luzem
```

E2E: `/api/games/` = 3 gry; `/api/manifest/` = 3 wpisy z plikami; szczegół Hollow
Knight ma `folder == "Hollow Knight"`; skan raportuje `loose_files == 2`.

## 4. Aplikacja

### 4.1 Modele i klient

- `GameSummary.folder`, `GameDetail.folder` (`String`).
- `ManifestEntry { int gameId; String systemCode; String folder; List<GameFileModel> files; }` + `fromJson/toJson`.
- `ApiClient.fetchManifest() -> Future<List<ManifestEntry>>`.
- `LibrarySnapshot.manifest: List<ManifestEntry>`; `LibraryCache` zapisuje i czyta `manifest` (brak klucza w starym pliku → pusta lista).

### 4.2 Ścieżki (`core/downloads/storage_settings.dart`)

```dart
String gameDir(String systemCode, String folder) => '${dirFor(systemCode)}/$folder';
String pathFor(String systemCode, String folder, String fileName) =>
    '${gameDir(systemCode, folder)}/$fileName';
```

`buildTask`: `directory: settings.gameDir(systemCode, folder)`, `filename: file.name`
(gdy `name` zawiera podkatalog, `directory` dostaje jego część, `filename` basename).

### 4.3 Skan urządzenia (`core/downloads/device_scan.dart`)

```dart
class DeviceIndex {
  /// systemCode -> folder -> (relativeName -> size)
  final Map<String, Map<String, Map<String, int>>> games;
  /// wpisy nieznane: pliki luzem w katalogu systemu i foldery spoza manifestu
  final List<UnknownEntry> unknown;   // {systemCode, path, bytes, isDirectory}
}

DeviceIndex scanDevice(StorageSettings settings, Iterable<String> systemCodes,
    Set<(String, String)> knownFolders);   // synchroniczne dart:io
Map<int, LocalGameState> buildLocalStates(
    List<ManifestEntry> manifest, DeviceIndex index, StorageSettings settings);
```

`diffGame` przyjmuje dodatkowo `folder` i liczy `presentPaths` przez nowe `pathFor`.

### 4.4 Providery

- `deviceIndexProvider` (`AsyncNotifier<Map<int, LocalGameState>>`): `build()` czeka na
  `librarySnapshotProvider` i `storageSettingsProvider`, skanuje, zwraca mapę. Metoda
  `refresh()` przelicza (skan + diff) bez ponownego pobierania biblioteki.
- `unknownOnDeviceProvider` (`Provider<List<UnknownEntry>>`) z tego samego skanu.
- `localStateProvider(id)` → `Provider.family<LocalGameState, int>` czytający mapę;
  gra nieobecna w manifeście → `InstallStatus.none`.
- `installedIdsProvider`, `updatableIdsProvider` → `Provider<Set<int>>` wyprowadzone
  z mapy. Klasa `IdSet` i wpisy w `InstallBadge` znikają; odznaka tylko wyświetla.
- Wyzwalacze `refresh()`: `DownloadManager.onGameChanged`, `confirmAndDelete`,
  zapis katalogu ROMów / folderu per system (invalidate `storageSettingsProvider`
  odświeża przez zależność), pull-to-refresh (invalidate snapshotu → `build()`).

### 4.5 Ekrany

- Karta gry: nagłówek i przyciski bez zmian; `presentPaths` i cel pobierania liczone
  przez `pathFor(system, folder, name)`; usuwanie kasuje pliki, a potem pusty katalog
  gry (`Directory.deleteSync()` gdy `listSync().isEmpty`).
- Ustawienia, karta „Urządzenie": wiersz `Nieznane na urządzeniu` z liczbą i sumą
  rozmiarów; tap otwiera dialog z listą ścieżek (względem `<roms>`) i przyciskami
  `Zamknij` / `Usuń wszystko` (usuwa wymienione pliki i foldery rekurencyjnie, tylko
  pod `<roms>/<system>/`, potem `refresh()`). Gdy lista pusta, wiersz pokazuje `0`.
- Pobierania: bez zmian (kontynuują z `GameProgress`).

### 4.6 Aplikacja — testy

- Jednostkowe: `gameDir`/`pathFor`, `buildTask` z podkatalogiem, `scanDevice` na
  katalogu tymczasowym (foldery znane/nieznane, pliki luzem, brak katalogu systemu),
  `buildLocalStates` (installed / partial / update / none), cache z manifestem i bez.
- Widgetowe: odznaki i chipy zasilane mapą (bez `apiClientProvider`), wiersz „Nieznane
  na urządzeniu" z dialogiem i usuwaniem (pliki tymczasowe), usuwanie gry kasuje pusty
  folder, karta gry z `folder` w ścieżce.
- E2E `download_flow_test`: plik pod `<base>/snes/Super Mario World (USA)/Super Mario
  World (USA).sfc`; po usunięciu brak pliku i brak katalogu gry.
- Bramka 100% i lista wyłączeń bez zmian.

## 5. Wdrożenie

1. Backend: migracja, `docker compose up -d --build`, uporządkowanie biblioteki na
   NAS-ie (każda gra w folderze), `manage.py scan`, przegląd `LooseFile` w adminie.
2. Lokalnie u Jana: `library/gbc/Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc` →
   `library/gbc/Pokemon - Crystal Version/…` (część zadania, nie ręcznie).
3. Aplikacja 0.3.0: pliki pobrane płasko pokażą się jako „Nieznane na urządzeniu".
