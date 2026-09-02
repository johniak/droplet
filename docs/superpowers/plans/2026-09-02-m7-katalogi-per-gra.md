# M7 — katalog per gra i skan urządzenia: plan implementacji

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Jedna gra = jeden katalog na serwerze i na telefonie; stan „zainstalowana" liczony jednym skanem urządzenia względem manifestu całej biblioteki, bez zapytań per gra.

**Architecture:** Backend: skaner grupuje po podkatalogach systemu, pliki luzem trafiają do `LooseFile`, `Game.folder` jest tożsamością gry, API dostaje `folder` i `GET /api/manifest/`. Aplikacja: ścieżka `<roms>/<system>/<folder>/<plik>`, moduł `device_scan.dart` (skan + diff → `Map<int, LocalGameState>`), `deviceIndexProvider` zasilający odznaki, filtry, półki i kartę gry; `localStateProvider(id)` staje się odczytem z mapy; „Nieznane na urządzeniu" w Ustawieniach.

**Tech Stack:** Django 6 / DRF / pytest-cov (bramka 100%), Flutter 3.32 / Riverpod 3 / go_router 17 / background_downloader (bramka 100% przez `scripts/check_coverage_app.sh`).

**Spec:** `docs/superpowers/specs/2026-09-02-m7-katalogi-per-gra-design.md`

## Global Constraints

- Backend: `cd backend && pytest` musi przejść z bramką pokrycia 100% (konfiguracja w `pyproject.toml`); biegi częściowe z `--no-cov`. Testy nie dotykają sieci (autouse `_no_network`).
- Aplikacja: `./scripts/check_coverage_app.sh` = 100.00%, `flutter analyze` czysto; jedyne `coverage:ignore-file` w `lib/core/platform/*_port.dart`; `main()` w ignore-start/end.
- Testy widgetowe: **nigdy** `Future.delayed` w ciele `testWidgets`; dart:io tylko synchronicznie (`createTempSync`, `listSync`, `deleteSync`); komendy testowe z twardym limitem czasu (Bash timeout ≤ 300 s dla pliku, ≤ 600 s dla suity).
- Kontrakt API: `folder` w liście i szczególe gry = nazwa katalogu gry (bez systemu); `GET /api/manifest/` bez paginacji; `files[].name` = ścieżka względem katalogu gry (dla płaskiego katalogu to basename).
- Ścieżki w aplikacji tylko przez `StorageSettings.gameDir/pathFor` — żadnych ręcznych `'$a/$b'` poza tym plikiem.
- Napisy po polsku wg specu: `Nieznane na urządzeniu`, `Zamknij`, `Usuń wszystko`, `Do uporządkowania` (admin), `luzem` (kolumna admin).
- Teksty błędów przez `humanizeError`; żadnych `e.toString()` w UI.
- Klucze testowe zachowane (`back-button`, `nav-*`, `base-dir-field`, `grant-permission`, `wifi-only`, `system-dir-{code}`); nowe: `unknown-on-device`, `unknown-delete-all`.
- Commity po każdym tasku z trailerami Claude; brak nowych zależności po obu stronach.

---

## Mapa plików

| Plik | Odpowiedzialność |
|---|---|
| `backend/library/models.py`, `migrations/0002_folders.py` | `Game.folder`, `LooseFile`, `ScanRun.loose_files` |
| `backend/library/scanner/grouping.py` | folder = gra, `LooseEntry`, role wewnątrz katalogu |
| `backend/library/scanner/scan.py` | sync po `folder`, `LooseFile`, liczniki |
| `backend/library/admin.py` | `LooseFileAdmin`, kolumna `luzem`, `loose_files` w ScanRun |
| `backend/library/serializers.py`, `api.py`, `urls.py` | `folder`, `name` z podścieżką, `ManifestView` |
| `backend/e2e/fixture-library/**`, `backend/e2e/test_*.py` | fixture w folderach, asercje manifestu |
| `app/lib/core/api/models.dart`, `api_client.dart` | `folder`, `ManifestEntry`, `fetchManifest` |
| `app/lib/core/cache/library_cache.dart` | manifest w cache |
| `app/lib/core/downloads/storage_settings.dart`, `task_builder.dart`, `local_state.dart` | ścieżki z folderem |
| `app/lib/core/downloads/device_scan.dart` (nowy) | `scanDevice`, `buildLocalStates`, `UnknownEntry`; zastępuje `local_scanner.dart` |
| `app/lib/features/library/providers.dart` | `LibrarySnapshot.manifest`, `deviceIndexProvider`, `unknownOnDeviceProvider`, pochodne zbiory id |
| `app/lib/features/game/providers.dart`, `delete_dialog.dart` | `localStateProvider` z mapy; usuwanie z rmdir + refresh |
| `app/lib/core/downloads/download_manager.dart` | cel pobierania z folderem; `onGameChanged` → refresh |
| `app/lib/features/library/widgets/install_badge.dart` | tylko wyświetlanie |
| `app/lib/features/settings/settings_screen.dart` | wiersz i dialog „Nieznane na urządzeniu" |
| `app/integration_test/download_flow_test.dart`, `app/pubspec.yaml`, `RALPH-STATUS.md`, `docs/deploy.md` | e2e, wersja, dokumentacja |

---

### Task 1: Model, migracja, admin

**Files:**
- Modify: `backend/library/models.py`
- Create: `backend/library/migrations/0002_folders.py`
- Modify: `backend/library/admin.py`
- Test: `backend/library/tests/test_models.py`, `backend/library/tests/test_admin.py`

**Interfaces:**
- Produces: `Game.folder: CharField(max_length=1000, default="")` z `UniqueConstraint(fields=["folder"], condition=~Q(folder=""), name="uniq_game_folder")` (puste `folder` dozwolone wielokrotnie — obiekty sprzed migracji i fixtures testowe); usunięty `uniq_game_per_system`. `LooseFile(system FK related_name="loose_files", relative_path unique, size BigInteger)`. `ScanRun.loose_files: IntegerField(default=0)`. Admin: `LooseFileAdmin` (readonly, filtr po systemie, nagłówek „Do uporządkowania"), `SystemAdmin.loose_count` („luzem"), `ScanRunAdmin.list_display += ["loose_files"]`.

- [ ] **Step 1: Testy modeli i admina**

Dopisz do `backend/library/tests/test_models.py`:

```python
import pytest
from django.db import IntegrityError

from library.models import Game, LooseFile, ScanRun, System


@pytest.mark.django_db
def test_two_games_may_share_title_but_not_folder():
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    Game.objects.create(system=snes, folder="snes/Zelda (USA)", title="Zelda",
                        normalized_title="zelda")
    Game.objects.create(system=snes, folder="snes/Zelda (EUR)", title="Zelda",
                        normalized_title="zelda")
    with pytest.raises(IntegrityError):
        Game.objects.create(system=snes, folder="snes/Zelda (USA)", title="Zelda 2",
                            normalized_title="zelda 2")


@pytest.mark.django_db
def test_empty_folder_is_allowed_many_times():
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    Game.objects.create(system=snes, title="A", normalized_title="a")
    Game.objects.create(system=snes, title="B", normalized_title="b")
    assert Game.objects.filter(folder="").count() == 2


@pytest.mark.django_db
def test_loose_file_str_and_scanrun_counter():
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    lf = LooseFile.objects.create(system=snes, relative_path="snes/x.sfc", size=3)
    assert str(lf) == "snes/x.sfc"
    assert ScanRun.objects.create().loose_files == 0
```

Dopisz do `backend/library/tests/test_admin.py` (użyj istniejącej fixture `admin_client_` lub tej, którą plik już definiuje):

```python
@pytest.mark.django_db
def test_loose_file_admin_lists_and_filters(admin_client_):
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    psx = System.objects.create(code="psx", name="PSX", directory="psx")
    LooseFile.objects.create(system=snes, relative_path="snes/a.sfc", size=1)
    LooseFile.objects.create(system=psx, relative_path="psx/b.bin", size=2)
    page = admin_client_.get("/admin/library/loosefile/")
    assert page.status_code == 200
    assert b"snes/a.sfc" in page.content and b"psx/b.bin" in page.content
    filtered = admin_client_.get(f"/admin/library/loosefile/?system__id__exact={snes.pk}")
    assert b"snes/a.sfc" in filtered.content and b"psx/b.bin" not in filtered.content


@pytest.mark.django_db
def test_system_admin_shows_loose_count(admin_client_):
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    LooseFile.objects.create(system=snes, relative_path="snes/a.sfc", size=1)
    page = admin_client_.get("/admin/library/system/")
    assert page.status_code == 200
    assert b">1<" in page.content  # kolumna „luzem"


@pytest.mark.django_db
def test_scanrun_admin_shows_loose_files(admin_client_):
    ScanRun.objects.create(loose_files=4, status=ScanRun.Status.SUCCESS)
    page = admin_client_.get("/admin/library/scanrun/")
    assert b">4<" in page.content
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd backend && pytest --no-cov library/tests/test_models.py library/tests/test_admin.py -q`

- [ ] **Step 3: Model**

W `models.py`:

```python
from django.db.models import Q

class Game(models.Model):
    system = models.ForeignKey(System, on_delete=models.CASCADE, related_name="games")
    # Ścieżka katalogu gry względem biblioteki, np. "snes/Super Mario World (USA)".
    # Tożsamość gry; pusta tylko dla rekordów sprzed M7 (usuwa je pierwszy skan).
    folder = models.CharField(max_length=1000, default="", blank=True)
    title = models.CharField(max_length=500)
    normalized_title = models.CharField(max_length=500, db_index=True)
    switch_title_prefix = models.CharField(max_length=12, blank=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["title"]
        constraints = [
            models.UniqueConstraint(
                fields=["folder"], condition=~Q(folder=""), name="uniq_game_folder"
            )
        ]


class LooseFile(models.Model):
    """Plik leżący bezpośrednio w katalogu systemu — poza biblioteką, do uporządkowania."""

    system = models.ForeignKey(System, on_delete=models.CASCADE, related_name="loose_files")
    relative_path = models.CharField(max_length=1000, unique=True)
    size = models.BigIntegerField()

    class Meta:
        ordering = ["relative_path"]
        verbose_name = "plik do uporządkowania"
        verbose_name_plural = "Do uporządkowania"

    def __str__(self) -> str:
        return self.relative_path
```

`ScanRun`: `loose_files = models.IntegerField(default=0)`.

- [ ] **Step 4: Migracja**

`python manage.py makemigrations library -n folders`, potem dopisz do wygenerowanej migracji operację danych po `AddField(folder)`:

```python
import posixpath

def fill_folder(apps, schema_editor):
    Game = apps.get_model("library", "Game")
    for game in Game.objects.prefetch_related("files"):
        first = game.files.order_by("relative_path").first()
        if first is None:
            continue
        parent = posixpath.dirname(first.relative_path)
        # Plik bezpośrednio w katalogu systemu (jeden segment) → gra luzem: folder zostaje "".
        if parent and "/" in parent:
            game.folder = parent
            game.save(update_fields=["folder"])

operations = [..., migrations.RunPython(fill_folder, migrations.RunPython.noop), ...]
```

Kolejność w migracji: `RemoveConstraint(uniq_game_per_system)`, `AddField(folder)`, `RunPython(fill_folder)`, `AddConstraint(uniq_game_folder)`, `CreateModel(LooseFile)`, `AddField(ScanRun.loose_files)`. Dodaj test migracji danych w `test_models.py`:

```python
@pytest.mark.django_db
def test_fill_folder_derives_from_first_file():
    from importlib import import_module
    from django.apps import apps as global_apps
    mod = import_module("library.migrations.0002_folders")
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=snes, title="Mario", normalized_title="mario")
    GameFile.objects.create(game=g, relative_path="snes/Mario (USA)/m.sfc", size=1, mtime_ns=1)
    loose = Game.objects.create(system=snes, title="Loose", normalized_title="loose")
    GameFile.objects.create(game=loose, relative_path="snes/l.sfc", size=1, mtime_ns=1)
    mod.fill_folder(global_apps, None)
    g.refresh_from_db(); loose.refresh_from_db()
    assert g.folder == "snes/Mario (USA)"
    assert loose.folder == ""
```

- [ ] **Step 5: Admin**

```python
from django.db.models import Count
from .models import Game, GameFile, LooseFile, ScanRun, System

@admin.register(System)
class SystemAdmin(admin.ModelAdmin):
    list_display = ["code", "name", "directory", "thumbnail_repo", "needs_config", "loose_count"]
    list_editable = ["thumbnail_repo", "needs_config"]
    list_filter = ["needs_config"]

    def get_queryset(self, request):
        return super().get_queryset(request).annotate(_loose=Count("loose_files"))

    @admin.display(description="luzem", ordering="_loose")
    def loose_count(self, obj):
        return obj._loose


@admin.register(LooseFile)
class LooseFileAdmin(admin.ModelAdmin):
    list_display = ["relative_path", "system", "size"]
    list_filter = ["system"]
    search_fields = ["relative_path"]
    readonly_fields = ["system", "relative_path", "size"]

    def has_add_permission(self, request):
        return False
```

`ScanRunAdmin.list_display` + `"loose_files"`. `GameAdmin.list_display` + `"folder"` i `search_fields` + `"folder"`.

- [ ] **Step 6: Testy i bramka**

Run: `cd backend && pytest -q`
Expected: PASS, pokrycie 100%. Jeśli gałąź `has_add_permission` lub `loose_count` nie jest pokryta — testy wyżej ją pokrywają (lista systemów wywołuje `loose_count`; dodaj `assert admin_client_.get("/admin/library/loosefile/add/").status_code == 403`).

- [ ] **Step 7: Commit**

```bash
git add backend/library
git commit -m "feat(library): Game.folder, LooseFile i licznik luzem w skanie"
```

---

### Task 2: Grupowanie — katalog = gra

**Files:**
- Modify: `backend/library/scanner/grouping.py`
- Test: `backend/library/tests/test_grouping.py` (zastąp)

**Interfaces:**
- Produces: `@dataclass LooseEntry(relative_path: str, size: int)`; `GameGroup.folder: str` (np. `"snes/Super Mario World (USA)"`); `group_system_dir(system_dir, library_root, *, is_switch) -> tuple[list[GameGroup], list[LooseEntry]]`; stała `SIDECAR_EXTENSIONS`.
- Role: m3u → `support` + płyty `disc`/`support`; samodzielne cue → `base` + bin `support`; Switch → `parse_switch` (`base`/`update`/`dlc`, wersja), `switch_title_prefix` z pliku `base`; sidecar → `other`; reszta → `base`.

- [ ] **Step 1: Testy**

```python
# backend/library/tests/test_grouping.py
from library.scanner.grouping import SIDECAR_EXTENSIONS, group_system_dir


def _write(p, content=b"x"):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(content)


def _by_title(groups):
    return {g.title: g for g in groups}


def test_each_folder_is_one_game_and_loose_files_are_reported(tmp_path):
    root = tmp_path
    _write(root / "snes" / "Super Mario World (USA)" / "Super Mario World (USA).sfc")
    _write(root / "snes" / "F-Zero (USA)" / "F-Zero (USA).sfc")
    _write(root / "snes" / "Loose (USA).sfc", b"loose")
    _write(root / "snes" / ".hidden" / "x.sfc")
    groups, loose = group_system_dir(root / "snes", root, is_switch=False)
    assert sorted(g.folder for g in groups) == ["snes/F-Zero (USA)", "snes/Super Mario World (USA)"]
    g = _by_title(groups)["Super Mario World"]
    assert g.normalized_title == "super mario world"
    assert g.files[0].relative_path == "snes/Super Mario World (USA)/Super Mario World (USA).sfc"
    assert g.files[0].role == "base"
    assert [(l.relative_path, l.size) for l in loose] == [("snes/Loose (USA).sfc", 5)]


def test_title_comes_from_folder_not_files(tmp_path):
    root = tmp_path
    _write(root / "gba" / "Metroid Fusion (USA)" / "mf.gba")
    _write(root / "gba" / "Metroid Fusion (USA)" / "readme.txt")
    groups, _ = group_system_dir(root / "gba", root, is_switch=False)
    g = groups[0]
    assert g.title == "Metroid Fusion"
    roles = {f.relative_path.split("/")[-1]: f.role for f in g.files}
    assert roles == {"mf.gba": "base", "readme.txt": "other"}
    assert ".txt" in SIDECAR_EXTENSIONS


def test_cue_bin_inside_folder(tmp_path):
    root = tmp_path
    d = root / "psx" / "Tekken (USA)"
    _write(d / "Tekken (USA).cue", b'FILE "Tekken (USA).bin" BINARY\n')
    _write(d / "Tekken (USA).bin")
    groups, _ = group_system_dir(root / "psx", root, is_switch=False)
    roles = {f.relative_path.split("/")[-1]: f.role for f in groups[0].files}
    assert roles == {"Tekken (USA).cue": "base", "Tekken (USA).bin": "support"}


def test_m3u_multidisc_inside_folder_with_subdirs(tmp_path):
    root = tmp_path
    d = root / "psx" / "FF7"
    _write(d / "disc1" / "FF7 (Disc 1).cue", b'FILE "FF7 (Disc 1).bin" BINARY\n')
    _write(d / "disc1" / "FF7 (Disc 1).bin")
    _write(d / "disc2" / "FF7 (Disc 2).cue", b'FILE "FF7 (Disc 2).bin" BINARY\n')
    _write(d / "disc2" / "FF7 (Disc 2).bin")
    _write(d / "FF7.m3u", b"disc1/FF7 (Disc 1).cue\ndisc2/FF7 (Disc 2).cue\n")
    groups, _ = group_system_dir(root / "psx", root, is_switch=False)
    assert len(groups) == 1
    discs = sorted((f.disc_number, f.relative_path) for f in groups[0].files if f.role == "disc")
    assert discs == [(1, "psx/FF7/disc1/FF7 (Disc 1).cue"), (2, "psx/FF7/disc2/FF7 (Disc 2).cue")]
    assert sum(1 for f in groups[0].files if f.role == "support") == 3  # m3u + 2 bin


def test_m3u_missing_entry_is_skipped(tmp_path):
    root = tmp_path
    d = root / "psx" / "Game"
    _write(d / "Game (Disc 1).cue", b'FILE "Game (Disc 1).bin" BINARY\n')
    _write(d / "Game (Disc 1).bin")
    _write(d / "Game.m3u", b"Game (Disc 1).cue\nGame (Disc 2).cue\n")
    groups, _ = group_system_dir(root / "psx", root, is_switch=False)
    assert [f.disc_number for f in groups[0].files if f.role == "disc"] == [1]


def test_switch_folder_roles_and_prefix(tmp_path):
    root = tmp_path
    d = root / "switch" / "Hollow Knight"
    _write(d / "Hollow Knight [0100633007D48000][v0].nsp")
    _write(d / "Hollow Knight [UPD][0100633007D48800][v196608].nsp")
    _write(d / "Hollow Knight [DLC][0100633007D49001].nsp")
    groups, _ = group_system_dir(root / "switch", root, is_switch=True)
    g = groups[0]
    assert g.title == "Hollow Knight"
    assert g.switch_title_prefix == "0100633007D4"
    roles = sorted((f.role, f.version) for f in g.files)
    assert roles == [("base", ""), ("dlc", ""), ("update", "v196608")]


def test_switch_folder_without_base_has_no_prefix(tmp_path):
    root = tmp_path
    _write(root / "switch" / "Only Update" / "X [UPD][0100633007D48800][v1].nsp")
    groups, _ = group_system_dir(root / "switch", root, is_switch=True)
    assert groups[0].switch_title_prefix == ""
    assert groups[0].files[0].role == "update"


def test_empty_folder_yields_no_game(tmp_path):
    (tmp_path / "snes" / "Empty").mkdir(parents=True)
    groups, loose = group_system_dir(tmp_path / "snes", tmp_path, is_switch=False)
    assert groups == [] and loose == []
```

Sprawdź w `library/scanner/switch.py`, jak `title_prefix` skraca title-id (test zakłada 12 znaków, tak jak `Game.switch_title_prefix max_length=12`); jeśli inaczej, dopasuj oczekiwaną wartość w teście do rzeczywistego wyniku `title_prefix("0100633007D48000")`.

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd backend && pytest --no-cov library/tests/test_grouping.py -q`

- [ ] **Step 3: Implementacja**

```python
"""Group one system directory into games: every sub-directory is one game.

Pure filesystem logic — no ORM — so it can be tested on temporary trees.
"""

from dataclasses import dataclass, field
from pathlib import Path

from .naming import display_title, normalize_title
from .playlists import parse_cue, parse_m3u
from .switch import parse_switch, title_prefix

SIDECAR_EXTENSIONS = frozenset(
    {".txt", ".nfo", ".md", ".jpg", ".jpeg", ".png", ".pdf", ".sav", ".srm",
     ".state", ".xml", ".json"}
)


@dataclass
class FileEntry:
    relative_path: str
    role: str
    disc_number: int | None
    version: str
    size: int
    mtime_ns: int


@dataclass
class GameGroup:
    folder: str
    title: str
    normalized_title: str
    switch_title_prefix: str = ""
    files: list[FileEntry] = field(default_factory=list)


@dataclass
class LooseEntry:
    relative_path: str
    size: int


def _entry(path: Path, root: Path, role: str, disc=None, version="") -> FileEntry:
    st = path.stat()
    return FileEntry(
        relative_path=path.relative_to(root).as_posix(),
        role=role, disc_number=disc, version=version,
        size=st.st_size, mtime_ns=st.st_mtime_ns,
    )


def _hidden(path: Path, root: Path) -> bool:
    return any(part.startswith(".") for part in path.relative_to(root).parts)


def _group_folder(folder: Path, root: Path, *, is_switch: bool) -> GameGroup | None:
    files = sorted(p for p in folder.rglob("*") if p.is_file() and not _hidden(p, root))
    if not files:
        return None
    file_set = set(files)
    group = GameGroup(
        folder=folder.relative_to(root).as_posix(),
        title=display_title(folder.name),
        normalized_title=normalize_title(folder.name),
    )
    claimed: set[Path] = set()

    def resolve(base: Path, name: str) -> Path | None:
        cand = (base.parent / name)
        return cand if cand in file_set else None

    # 1. m3u: płyty z numerami, cue/bin jako support
    for m3u in [p for p in files if p.suffix.lower() == ".m3u"]:
        group.files.append(_entry(m3u, root, "support"))
        claimed.add(m3u)
        for i, name in enumerate(parse_m3u(m3u.read_text(errors="replace")), start=1):
            disc = resolve(m3u, name)
            if disc is None:
                continue
            group.files.append(_entry(disc, root, "disc", disc=i))
            claimed.add(disc)
            if disc.suffix.lower() == ".cue":
                for bin_name in parse_cue(disc.read_text(errors="replace")):
                    b = resolve(disc, bin_name)
                    if b is not None and b not in claimed:
                        group.files.append(_entry(b, root, "support"))
                        claimed.add(b)

    # 2. samodzielne cue
    for cue in [p for p in files if p.suffix.lower() == ".cue" and p not in claimed]:
        group.files.append(_entry(cue, root, "base"))
        claimed.add(cue)
        for bin_name in parse_cue(cue.read_text(errors="replace")):
            b = resolve(cue, bin_name)
            if b is not None and b not in claimed:
                group.files.append(_entry(b, root, "support"))
                claimed.add(b)

    # 3. reszta: Switch wg tagów, sidecar jako other, inne jako base
    for p in files:
        if p in claimed:
            continue
        if is_switch:
            info = parse_switch(p.stem)
            if info.role == "base" and info.title_id and not group.switch_title_prefix:
                group.switch_title_prefix = title_prefix(info.title_id)
            group.files.append(_entry(p, root, info.role, version=info.version))
        elif p.suffix.lower() in SIDECAR_EXTENSIONS:
            group.files.append(_entry(p, root, "other"))
        else:
            group.files.append(_entry(p, root, "base"))
    return group


def group_system_dir(
    system_dir: Path, library_root: Path, *, is_switch: bool
) -> tuple[list[GameGroup], list[LooseEntry]]:
    groups: list[GameGroup] = []
    loose: list[LooseEntry] = []
    for child in sorted(system_dir.iterdir()):
        if _hidden(child, library_root):
            continue
        if child.is_dir():
            group = _group_folder(child, library_root, is_switch=is_switch)
            if group is not None:
                groups.append(group)
        elif child.is_file():
            loose.append(
                LooseEntry(child.relative_to(library_root).as_posix(), child.stat().st_size)
            )
    return groups, loose
```

Uwaga: `parse_switch` dla pliku bez tagów zwraca `role == "base"` (sprawdź w `switch.py`; jeśli zwraca coś innego, `.nsp` bez tagów ma być `base`).

- [ ] **Step 4: Testy**

Run: `cd backend && pytest --no-cov library/tests/test_grouping.py library/tests/test_switch.py library/tests/test_playlists.py -q`
Expected: PASS. (Testy skanu z Task 3 będą chwilowo czerwone — Task 3 je przepisuje; do commitu tego taska uruchom tylko powyższe pliki.)

- [ ] **Step 5: Commit**

```bash
git add backend/library/scanner/grouping.py backend/library/tests/test_grouping.py
git commit -m "feat(scanner): katalog = gra, pliki luzem jako LooseEntry"
```

---

### Task 3: Synchronizacja skanu

**Files:**
- Modify: `backend/library/scanner/scan.py`
- Test: `backend/library/tests/test_scan.py` (zastąp), `backend/library/tests/test_scan_triggers.py` (dopasuj fixture do folderów, jeśli tworzy pliki)

**Interfaces:**
- Consumes: `group_system_dir -> (groups, loose)`, `GameGroup.folder`, `LooseEntry`.
- Produces: `_find_game(system, group)` po `folder`; `LooseFile` zastępowany po skanie; `run.loose_files`; `Game` tworzone z `folder`; usuwanie nieaktualnych plików/gier jak dziś (obejmuje gry z `folder == ""` po migracji).

- [ ] **Step 1: Testy**

```python
# backend/library/tests/test_scan.py
import pytest
from django.test import override_settings

from library.models import Game, GameFile, LooseFile, ScanRun, System
from library.scanner.scan import run_scan


def _write(p, content=b"x"):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(content)


@pytest.fixture
def library(tmp_path):
    _write(tmp_path / "snes" / "Super Mario World (USA)" / "Super Mario World (USA).sfc", b"a" * 10)
    _write(tmp_path / "snes" / "F-Zero (USA)" / "F-Zero (USA).sfc", b"b" * 20)
    _write(tmp_path / "snes" / "Loose (USA).sfc", b"c" * 5)
    return tmp_path


@pytest.mark.django_db
def test_initial_scan_creates_games_and_loose(library):
    with override_settings(LIBRARY_ROOT=library):
        run = run_scan()
    assert run.status == ScanRun.Status.SUCCESS
    assert Game.objects.count() == 2
    assert Game.objects.get(title="F-Zero").folder == "snes/F-Zero (USA)"
    assert GameFile.objects.count() == 2
    assert LooseFile.objects.get().relative_path == "snes/Loose (USA).sfc"
    assert run.loose_files == 1 and run.files_created == 2


@pytest.mark.django_db
def test_rescan_is_idempotent(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        run2 = run_scan()
    assert (run2.files_created, run2.files_updated, run2.files_deleted) == (0, 0, 0)
    assert LooseFile.objects.count() == 1 and run2.loose_files == 1


@pytest.mark.django_db
def test_loose_file_moved_into_folder_becomes_game(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        src = library / "snes" / "Loose (USA).sfc"
        _write(library / "snes" / "Loose (USA)" / "Loose (USA).sfc", src.read_bytes())
        src.unlink()
        run2 = run_scan()
    assert LooseFile.objects.count() == 0
    assert Game.objects.filter(folder="snes/Loose (USA)").exists()
    assert run2.games_created == 1


@pytest.mark.django_db
def test_renamed_folder_is_new_game_and_old_one_goes(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        (library / "snes" / "F-Zero (USA)").rename(library / "snes" / "F-Zero (EUR)")
        run2 = run_scan()
    assert not Game.objects.filter(folder="snes/F-Zero (USA)").exists()
    assert Game.objects.get(folder="snes/F-Zero (EUR)").title == "F-Zero"
    assert run2.files_deleted == 1 and run2.files_created == 1


@pytest.mark.django_db
def test_deleted_folder_removes_game(library):
    import shutil
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        shutil.rmtree(library / "snes" / "F-Zero (USA)")
        run2 = run_scan()
    assert run2.files_deleted == 1
    assert not Game.objects.filter(title="F-Zero").exists()


@pytest.mark.django_db
def test_modified_file_updates_size(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        (library / "snes" / "F-Zero (USA)" / "F-Zero (USA).sfc").write_bytes(b"c" * 99)
        run2 = run_scan()
    assert run2.files_updated == 1
    assert GameFile.objects.get(relative_path__endswith="F-Zero (USA).sfc").size == 99


@pytest.mark.django_db
def test_legacy_game_without_folder_is_removed_on_first_scan(library):
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    legacy = Game.objects.create(system=snes, title="Old", normalized_title="old")
    GameFile.objects.create(game=legacy, relative_path="snes/Old.sfc", size=1, mtime_ns=1)
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
    assert not Game.objects.filter(title="Old").exists()


@pytest.mark.django_db
def test_two_folders_same_title_are_two_games(tmp_path):
    _write(tmp_path / "snes" / "Zelda (USA)" / "z.sfc")
    _write(tmp_path / "snes" / "Zelda (EUR)" / "z.sfc")
    with override_settings(LIBRARY_ROOT=tmp_path):
        run = run_scan()
    assert run.status == ScanRun.Status.SUCCESS
    assert Game.objects.filter(normalized_title="zelda").count() == 2


@pytest.mark.django_db
def test_missing_library_root_marks_run_failed(tmp_path):
    with override_settings(LIBRARY_ROOT=tmp_path / "nope"):
        run = run_scan()
    assert run.status == ScanRun.Status.FAILED and run.errors


@pytest.mark.django_db
def test_system_error_is_recorded_and_scan_continues(library, monkeypatch):
    def boom(*a, **k):
        raise OSError("disk")
    monkeypatch.setattr("library.scanner.scan.group_system_dir", boom)
    with override_settings(LIBRARY_ROOT=library):
        run = run_scan()
    assert run.status == ScanRun.Status.SUCCESS and "snes: disk" in run.errors
```

Zachowaj z obecnego pliku testy dotyczące systemów (`needs_config`, aliasy) — przenieś ich fixtures na układ z folderami.

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd backend && pytest --no-cov library/tests/test_scan.py -q`

- [ ] **Step 3: Implementacja**

```python
def _find_game(system: System, group) -> Game | None:
    return Game.objects.filter(folder=group.folder).first()


def _sync_group(system: System, group, run: ScanRun, seen: set[str]) -> None:
    game = _find_game(system, group)
    if game is None:
        game = Game.objects.create(
            system=system,
            folder=group.folder,
            title=group.title,
            normalized_title=group.normalized_title,
            switch_title_prefix=group.switch_title_prefix,
        )
        run.games_created += 1
    elif group.switch_title_prefix and game.switch_title_prefix != group.switch_title_prefix:
        game.switch_title_prefix = group.switch_title_prefix
        game.save(update_fields=["switch_title_prefix"])
    # pętla po entry jak dziś (create / update size+mtime)


def _sync_loose(all_loose: dict[str, tuple[System, int]]) -> None:
    """Zbiór LooseFile odzwierciedla dokładnie bieżący skan."""
    existing = {lf.relative_path: lf for lf in LooseFile.objects.all()}
    for path, lf in existing.items():
        if path not in all_loose:
            lf.delete()
    for path, (system, size) in all_loose.items():
        lf = existing.get(path)
        if lf is None:
            LooseFile.objects.create(system=system, relative_path=path, size=size)
        elif lf.size != size or lf.system_id != system.pk:
            lf.size, lf.system = size, system
            lf.save(update_fields=["size", "system"])
```

W `run_scan`: `all_loose: dict[str, tuple[System, int]] = {}`; w pętli systemów `groups, loose = group_system_dir(...)`; po `_sync_group` dla każdego `for l in loose: all_loose[l.relative_path] = (system, l.size)`; po pętli `_sync_loose(all_loose)`, `run.loose_files = len(all_loose)`. Usuwanie stale `GameFile` i pustych `Game` bez zmian (usuwa też gry legacy z `folder == ""`).

- [ ] **Step 4: Testy i bramka**

Run: `cd backend && pytest -q`
Expected: PASS, 100%. Testy w innych plikach tworzące `Game` bez `folder` działają (puste `folder` dozwolone). Jeśli `test_scan_triggers.py` lub testy okładek zakładają pliki luzem w bibliotece tymczasowej — przenieś je do folderów.

- [ ] **Step 5: Commit**

```bash
git add backend/library
git commit -m "feat(scanner): synchronizacja po katalogu gry i pliki do uporządkowania"
```

---

### Task 4: API — `folder`, nazwy z podścieżką, manifest; fixture e2e

**Files:**
- Modify: `backend/library/serializers.py`, `backend/library/api.py`, `backend/library/urls.py`
- Modify: `backend/e2e/fixture-library/**` (struktura), `backend/e2e/test_scan_e2e.py`, `backend/e2e/test_api_e2e.py`
- Test: `backend/library/tests/test_api_games.py`, `test_api_game_detail.py`, nowy `test_api_manifest.py`

**Interfaces:**
- Produces: `GameListSerializer.folder` (= `posixpath.basename(obj.folder)`), `GameDetailSerializer.folder`; `GameFileSerializer.name` = `relative_path` względem `game.folder` (gdy `folder` puste → basename); `ManifestView` (`GET /api/manifest/`, `ListAPIView`, `pagination_class = None`, `ordering by id`, `prefetch_related("files")`), `ManifestEntrySerializer` `{id, system_code, folder, files:[{id, name, role, version, disc_number, size}]}` z plikami posortowanymi jak w szczególe.

- [ ] **Step 1: Testy**

`backend/library/tests/test_api_manifest.py`:

```python
import pytest

from library.models import Game, GameFile, System


@pytest.fixture
def two_games(db):
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    psx = System.objects.create(code="psx", name="PSX", directory="psx")
    m = Game.objects.create(system=snes, folder="snes/Mario (USA)", title="Mario",
                            normalized_title="mario")
    GameFile.objects.create(game=m, relative_path="snes/Mario (USA)/Mario (USA).sfc",
                            size=10, mtime_ns=1)
    ff = Game.objects.create(system=psx, folder="psx/FF7", title="FF7", normalized_title="ff7")
    GameFile.objects.create(game=ff, relative_path="psx/FF7/disc1/FF7 (Disc 1).cue",
                            role="disc", disc_number=1, size=1, mtime_ns=1)
    GameFile.objects.create(game=ff, relative_path="psx/FF7/FF7.m3u", role="support",
                            size=2, mtime_ns=1)
    return m, ff


def test_manifest_lists_all_games_with_files(auth_client, two_games):
    body = auth_client.get("/api/manifest/").json()
    assert [e["id"] for e in body] == sorted(e["id"] for e in body)
    mario = next(e for e in body if e["folder"] == "Mario (USA)")
    assert mario["system_code"] == "snes"
    assert mario["files"] == [
        {"id": mario["files"][0]["id"], "name": "Mario (USA).sfc", "role": "base",
         "version": "", "disc_number": None, "size": 10}
    ]
    ff = next(e for e in body if e["folder"] == "FF7")
    assert [f["name"] for f in ff["files"]] == ["disc1/FF7 (Disc 1).cue", "FF7.m3u"]


def test_manifest_requires_auth(client, two_games):
    assert client.get("/api/manifest/").status_code == 401


def test_manifest_is_empty_without_games(auth_client):
    assert auth_client.get("/api/manifest/").json() == []
```

Dopisz do `test_api_games.py`: lista zawiera `folder` (nazwa katalogu bez systemu) — utwórz grę z `folder="snes/Mario (USA)"` i sprawdź `results[0]["folder"] == "Mario (USA)"`; do `test_api_game_detail.py`: szczegół ma `folder`, a plik w podkatalogu gry ma `name == "disc1/x.cue"` (dodaj plik `relative_path="switch/Hollow Knight/dlc/hk-dlc.nsp"` przy `folder="switch/Hollow Knight"` i sprawdź `name == "dlc/hk-dlc.nsp"`); gra z pustym `folder` zwraca basename.

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd backend && pytest --no-cov library/tests/test_api_manifest.py library/tests/test_api_games.py library/tests/test_api_game_detail.py -q`

- [ ] **Step 3: Serializery i widok**

```python
# serializers.py
def _name_within_game(file: GameFile) -> str:
    folder = file.game.folder
    if folder and file.relative_path.startswith(folder + "/"):
        return file.relative_path[len(folder) + 1 :]
    return posixpath.basename(file.relative_path)


class GameListSerializer(serializers.ModelSerializer):
    system_code = serializers.CharField(source="system.code", read_only=True)
    has_cover = serializers.BooleanField(read_only=True)
    total_size = serializers.IntegerField(read_only=True)
    folder = serializers.SerializerMethodField()

    class Meta:
        model = Game
        fields = ["id", "title", "system_code", "has_cover", "total_size", "folder"]

    def get_folder(self, obj):
        return posixpath.basename(obj.folder)


class GameFileSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()
    # fields jak dziś

    def get_name(self, obj):
        return _name_within_game(obj)


def sorted_files(game):
    return sorted(
        game.files.all(),
        key=lambda f: (ROLE_ORDER.get(f.role, 9), f.disc_number or 0, f.relative_path),
    )


class ManifestFileSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()

    class Meta:
        model = GameFile
        fields = ["id", "name", "role", "version", "disc_number", "size"]

    def get_name(self, obj):
        return _name_within_game(obj)


class ManifestEntrySerializer(serializers.ModelSerializer):
    system_code = serializers.CharField(source="system.code", read_only=True)
    folder = serializers.SerializerMethodField()
    files = serializers.SerializerMethodField()

    class Meta:
        model = Game
        fields = ["id", "system_code", "folder", "files"]

    def get_folder(self, obj):
        return posixpath.basename(obj.folder)

    def get_files(self, obj):
        return ManifestFileSerializer(sorted_files(obj), many=True).data
```

`GameDetailSerializer.get_files` używa `sorted_files(obj)`. `GameFileSerializer` potrzebuje `game` — w widoku szczegółu `prefetch_related("files")` na obiekcie `Game`, więc `file.game` jest w cache (`obj.files.all()` ustawia `game` na instancji); w manifestach analogicznie.

```python
# api.py
class ManifestView(ListAPIView):
    serializer_class = ManifestEntrySerializer
    pagination_class = None

    def get_queryset(self):
        return Game.objects.select_related("system").prefetch_related("files").order_by("id")
```

`urls.py`: `path("manifest/", api.ManifestView.as_view(), name="manifest"),`.

- [ ] **Step 4: Fixture e2e i testy e2e**

Przenieś pliki (`git mv`):

```
backend/e2e/fixture-library/snes/Super Mario World (USA)/Super Mario World (USA).sfc
backend/e2e/fixture-library/psx/Tekken (USA)/Tekken (USA).cue
backend/e2e/fixture-library/psx/Tekken (USA)/Tekken (USA).bin
backend/e2e/fixture-library/switch/Hollow Knight/Hollow Knight [0100633007D48000][v0].nsp
backend/e2e/fixture-library/switch/Hollow Knight/Hollow Knight [UPD][0100633007D48800][v196608].nsp
```

Dodaj `backend/e2e/fixture-library/snes/Luzem (USA).sfc` (4 bajty). `Dziwny Folder/tajemniczy.rom` zostaje (plik luzem w systemie `needs_config`).

W `test_scan_e2e.py::test_scan_result_contents` dopisz:

```python
    manifest = requests.get(f"{base_url}/api/manifest/", headers=auth, timeout=10).json()
    by_folder = {e["folder"]: e for e in manifest}
    assert set(by_folder) == {"Super Mario World (USA)", "Tekken (USA)", "Hollow Knight"}
    assert {f["role"] for f in by_folder["Hollow Knight"]["files"]} == {"base", "update"}
    assert "Luzem" not in titles
```

W `test_api_e2e.py::test_full_flow` sprawdź `detail["folder"] == "Super Mario World (USA)"` (dopasuj do tego, którą grę test pobiera).

- [ ] **Step 5: Testy, bramka, e2e backendu**

Run: `cd backend && pytest -q && cd .. && ./scripts/e2e_backend.sh`
Expected: PASS, 100%; e2e backendu zielone (Docker wymagany; bez Dockera zapisz to w `RALPH-STATUS.md` jako krok do wykonania — nie udawaj).

- [ ] **Step 6: Commit**

```bash
git add backend
git commit -m "feat(api): folder gry, nazwy plików względem katalogu i /api/manifest/"
```

---

### Task 5: Aplikacja — modele, klient, cache, snapshot

**Files:**
- Modify: `app/lib/core/api/models.dart`, `app/lib/core/api/api_client.dart`, `app/lib/core/cache/library_cache.dart`, `app/lib/features/library/providers.dart` (`LibrarySnapshot`, `librarySnapshotProvider`)
- Test: `app/test/core/models_test.dart`, `app/test/core/api_client_test.dart`, `app/test/core/library_cache_test.dart`, `app/test/features/library_snapshot_test.dart`

**Interfaces:**
- Produces: `GameSummary.folder`, `GameDetail.folder` (wymagane, z JSON `folder`); `GameFileModel.toJson()`; `class ManifestEntry { int gameId; String systemCode; String folder; List<GameFileModel> files; fromJson/toJson }`; `ApiClient.fetchManifest()`; `CachedLibrary.manifest`, `LibraryCache.save(systems, games, manifest)`; `LibrarySnapshot.manifest` (pobierany razem z systemami i grami; offline z cache; stary cache bez klucza → `[]`).
- Każde wystąpienie `GameSummary(`/`GameDetail(` w testach dostaje `folder: '<tytuł>'` — najpierw `grep -rn "GameSummary(\|GameDetail(" app/test app/lib` i popraw wszystkie (to główny koszt tego taska).

- [ ] **Step 1: Testy**

`models_test.dart` — dopisz:

```dart
  test('ManifestEntry roundtrip and GameSummary.folder', () {
    final entry = ManifestEntry.fromJson({
      'id': 7,
      'system_code': 'switch',
      'folder': 'Hollow Knight',
      'files': [
        {'id': 1, 'name': 'hk.nsp', 'role': 'base', 'version': '', 'disc_number': null, 'size': 3},
      ],
    });
    expect(entry.gameId, 7);
    expect(entry.files.single.role, FileRole.base);
    expect(ManifestEntry.fromJson(entry.toJson()).files.single.name, 'hk.nsp');
    final g = GameSummary.fromJson({
      'id': 1, 'title': 'Mario', 'system_code': 'snes', 'has_cover': false,
      'total_size': 5, 'folder': 'Mario (USA)',
    });
    expect(g.folder, 'Mario (USA)');
    expect(GameSummary.fromJson(g.toJson()).folder, 'Mario (USA)');
  });
```

`api_client_test.dart` — dopisz `fetchManifest parses entries` (adapter `onGet('/api/manifest/')` z jedną pozycją, nagłówek tokenu, oczekiwany `List<ManifestEntry>` długości 1). `library_cache_test.dart` — roundtrip z manifestem oraz `load` starego pliku bez klucza `manifest` → `manifest` puste (zapisz ręcznie JSON bez klucza). `library_snapshot_test.dart` — fake klient zwraca manifest; snapshot online ma `manifest.length == N`; offline (DioException) bierze manifest z cache.

Uwaga do `GameFileModel.fromJson`: manifest nie ma `relative_path` — pole `relativePath` staje się opcjonalne (`(j['relative_path'] ?? '') as String`).

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd app && timeout 300 flutter test test/core/models_test.dart test/core/api_client_test.dart test/core/library_cache_test.dart test/features/library_snapshot_test.dart`

- [ ] **Step 3: Implementacja**

```dart
// models.dart — fragmenty
class GameSummary {
  const GameSummary({required this.id, required this.title, required this.systemCode,
      required this.hasCover, required this.totalSize, required this.folder});
  final String folder; // + w fromJson: j['folder'] as String, w toJson: 'folder': folder
}

class GameFileModel {
  // relativePath: (j['relative_path'] ?? '') as String
  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'relative_path': relativePath, 'role': role.name,
        'disc_number': discNumber, 'version': version, 'size': size,
      };
}

class ManifestEntry {
  const ManifestEntry({required this.gameId, required this.systemCode,
      required this.folder, required this.files});
  final int gameId;
  final String systemCode;
  final String folder;
  final List<GameFileModel> files;

  factory ManifestEntry.fromJson(Map<String, dynamic> j) => ManifestEntry(
        gameId: j['id'] as int,
        systemCode: j['system_code'] as String,
        folder: j['folder'] as String,
        files: [for (final f in j['files'] as List) GameFileModel.fromJson(f as Map<String, dynamic>)],
      );

  Map<String, dynamic> toJson() => {
        'id': gameId, 'system_code': systemCode, 'folder': folder,
        'files': [for (final f in files) f.toJson()],
      };
}
```

`api_client.dart`:

```dart
  Future<List<ManifestEntry>> fetchManifest() async {
    try {
      final resp = await _dio.get('/api/manifest/');
      return [for (final e in resp.data as List) ManifestEntry.fromJson(e as Map<String, dynamic>)];
    } on DioException catch (e) {
      _mapError(e);
    }
  }
```

`library_cache.dart`: `CachedLibrary.manifest`, `save(systems, games, manifest)` zapisuje `'manifest': [...]`, `load` czyta `(data['manifest'] as List?) ?? const []`.

`providers.dart`: `LibrarySnapshot.manifest` (wymagane); w `librarySnapshotProvider` po pobraniu gier `final manifest = await client.fetchManifest();`, `cache.save(systems, games, manifest)`; offline `previous.manifest`. Popraw wszystkie konstrukcje `LibrarySnapshot(` w testach (`manifest: const []`).

- [ ] **Step 4: Testy i bramka**

Run: `cd app && flutter analyze && timeout 600 flutter test && cd .. && ./scripts/check_coverage_app.sh`
Expected: PASS, 100%.

- [ ] **Step 5: Commit**

```bash
git add app
git commit -m "feat(app): folder gry i manifest biblioteki w modelach, kliencie i cache"
```

---

### Task 6: Ścieżki z folderem i skan urządzenia

**Files:**
- Modify: `app/lib/core/downloads/storage_settings.dart`, `task_builder.dart`, `local_state.dart`, `download_manager.dart`
- Create: `app/lib/core/downloads/device_scan.dart`
- Delete: `app/lib/core/downloads/local_scanner.dart`
- Test: `app/test/core/storage_settings_test.dart`, `task_builder_test.dart`, `local_state_test.dart`, `download_manager_test.dart`, nowy `device_scan_test.dart`

**Interfaces:**
- Produces:
  - `StorageSettings.gameDir(systemCode, folder)`, `pathFor(systemCode, folder, fileName)`; stare `pathFor(system, name)` znika.
  - `buildTask(..., folder: String)`: `directory = gameDir` + ewentualny podkatalog z `file.name`, `filename = basename(file.name)`.
  - `diffGame(files, sizesByName, settings, systemCode, folder)` — `presentPaths` przez nowe `pathFor`; klucze `sizesByName` to nazwy względem katalogu gry (z podkatalogami).
  - `device_scan.dart`:
    ```dart
    class UnknownEntry { final String systemCode; final String path; final int bytes; final bool isDirectory; }
    class DeviceIndex { final Map<String, Map<String, Map<String, int>>> games; final List<UnknownEntry> unknown; }
    DeviceIndex scanDevice(StorageSettings settings, Iterable<String> systemCodes, Set<String> knownFolderKeys /* '$system/$folder' */);
    Map<int, LocalGameState> buildLocalStates(List<ManifestEntry> manifest, DeviceIndex index, StorageSettings settings);
    ```
    `scanDevice`: dla każdego systemu `dirFor` → jeśli brak katalogu, pomiń; pliki bezpośrednio w nim → `unknown` (isDirectory=false, bytes=length); podkatalogi: gdy `'$system/$name'` w `knownFolderKeys` → mapa `relativeName → size` z `rglob` (ścieżki względem katalogu gry, separator `/`); inaczej `unknown` (isDirectory=true, bytes = suma rozmiarów rekurencyjnie).
  - `DownloadManager.downloadGame` liczy cel przez `settings.pathFor(game.systemCode, game.folder, file.name)` i przekazuje `folder` do `buildTask`.

- [ ] **Step 1: Testy**

`device_scan_test.dart`:

```dart
import 'dart:io';

import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/device_scan.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:flutter_test/flutter_test.dart';

GameFileModel f(int id, String name, FileRole role, {String version = '', int size = 4}) =>
    GameFileModel(id: id, name: name, relativePath: '', role: role, discNumber: null,
        version: version, size: size);

void main() {
  late Directory root;
  late StorageSettings settings;

  setUp(() {
    root = Directory.systemTemp.createTempSync('roms');
    settings = StorageSettings(root.path, const {});
  });
  tearDown(() => root.deleteSync(recursive: true));

  void put(String rel, [int size = 4]) {
    final file = File('${root.path}/$rel')..parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(size, 0));
  }

  test('known folders are indexed, everything else is unknown', () {
    put('snes/Mario (USA)/Mario (USA).sfc');
    put('snes/Zelda (USA)/z.sfc');          // nieznany folder
    put('snes/loose.sfc', 2);               // plik luzem
    put('psx/FF7/disc1/FF7 (Disc 1).bin', 8);
    final index = scanDevice(settings, ['snes', 'psx', 'gba'], {'snes/Mario (USA)', 'psx/FF7'});
    expect(index.games['snes']!['Mario (USA)'], {'Mario (USA).sfc': 4});
    expect(index.games['psx']!['FF7'], {'disc1/FF7 (Disc 1).bin': 8});
    expect(index.games.containsKey('gba'), isFalse);
    final unknown = {for (final u in index.unknown) u.path: (u.bytes, u.isDirectory)};
    expect(unknown, {
      '${root.path}/snes/Zelda (USA)': (4, true),
      '${root.path}/snes/loose.sfc': (2, false),
    });
  });

  test('buildLocalStates derives every game state from one index', () {
    put('snes/Mario (USA)/Mario (USA).sfc');
    put('switch/HK/hk.nsp');
    final manifest = [
      ManifestEntry(gameId: 1, systemCode: 'snes', folder: 'Mario (USA)',
          files: [f(1, 'Mario (USA).sfc', FileRole.base)]),
      ManifestEntry(gameId: 2, systemCode: 'switch', folder: 'HK',
          files: [f(2, 'hk.nsp', FileRole.base), f(3, 'upd.nsp', FileRole.update, version: 'v2')]),
      ManifestEntry(gameId: 3, systemCode: 'snes', folder: 'Absent',
          files: [f(4, 'a.sfc', FileRole.base)]),
    ];
    final index = scanDevice(settings, ['snes', 'switch'], {'snes/Mario (USA)', 'switch/HK', 'snes/Absent'});
    final states = buildLocalStates(manifest, index, settings);
    expect(states[1]!.status, InstallStatus.installed);
    expect(states[1]!.presentPaths, ['${root.path}/snes/Mario (USA)/Mario (USA).sfc']);
    expect(states[2]!.status, InstallStatus.partial);
    expect(states[2]!.updateAvailable, isTrue);
    expect(states[3]!.status, InstallStatus.none);
  });

  test('size mismatch means not present', () {
    put('snes/Mario (USA)/Mario (USA).sfc', 3);
    final manifest = [
      ManifestEntry(gameId: 1, systemCode: 'snes', folder: 'Mario (USA)',
          files: [f(1, 'Mario (USA).sfc', FileRole.base)]),
    ];
    final index = scanDevice(settings, ['snes'], {'snes/Mario (USA)'});
    expect(buildLocalStates(manifest, index, settings)[1]!.status, InstallStatus.none);
  });
}
```

`storage_settings_test.dart` — dopisz: `gameDir('snes','Mario (USA)') == '/roms/snes/Mario (USA)'`, `pathFor('snes','Mario (USA)','disc1/a.bin') == '/roms/snes/Mario (USA)/disc1/a.bin'`, z `systemDirs['snes']='SNES'` → `/roms/SNES/Mario (USA)`.
`task_builder_test.dart` — `buildTask(... folder: 'Mario (USA)')`: `directory == 'storage/emulated/0/RetroArch/roms/snes/Mario (USA)'`; dla `name: 'disc1/a.bin'` → `directory` kończy się `/Mario (USA)/disc1`, `filename == 'a.bin'`.
`local_state_test.dart` — `diffGame(files, sizes, settings, 'switch', 'HK')`, `presentPaths` z `/roms/switch/HK/…`.
`download_manager_test.dart` — fixture `GameDetail` ma `folder`; asercje na `task.directory` z folderem; test „plik już na dysku pomijany" używa nowej ścieżki.

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd app && timeout 300 flutter test test/core/device_scan_test.dart test/core/storage_settings_test.dart test/core/task_builder_test.dart test/core/local_state_test.dart test/core/download_manager_test.dart`

- [ ] **Step 3: Implementacja**

`storage_settings.dart`:

```dart
  String gameDir(String systemCode, String folder) => '${dirFor(systemCode)}/$folder';
  String pathFor(String systemCode, String folder, String fileName) =>
      '${gameDir(systemCode, folder)}/$fileName';
```

`task_builder.dart`:

```dart
DownloadTask buildTask({..., required String folder}) {
  final slash = file.name.lastIndexOf('/');
  final sub = slash < 0 ? '' : '/${file.name.substring(0, slash)}';
  final base = slash < 0 ? file.name : file.name.substring(slash + 1);
  return DownloadTask(
    ..., directory: '${settings.gameDir(systemCode, folder)}$sub', filename: base, ...);
}
```

`local_state.dart`: `diffGame(files, localSizesByName, settings, systemCode, folder)`; `presentPaths` → `settings.pathFor(systemCode, folder, file.name)`.

`device_scan.dart`:

```dart
import 'dart:io';

import '../api/models.dart';
import 'local_state.dart';
import 'storage_settings.dart';

class UnknownEntry {
  const UnknownEntry({required this.systemCode, required this.path, required this.bytes,
      required this.isDirectory});
  final String systemCode;
  final String path;
  final int bytes;
  final bool isDirectory;
}

class DeviceIndex {
  const DeviceIndex({required this.games, required this.unknown});
  /// systemCode -> folder -> (ścieżka względem katalogu gry -> rozmiar)
  final Map<String, Map<String, Map<String, int>>> games;
  final List<UnknownEntry> unknown;
}

String _rel(FileSystemEntity e, Directory base) =>
    e.path.substring(base.path.length + 1).replaceAll(Platform.pathSeparator, '/');

Map<String, int> _sizesUnder(Directory dir) => {
      for (final e in dir.listSync(recursive: true))
        if (e is File) _rel(e, dir): e.lengthSync(),
    };

/// Jeden synchroniczny przebieg po katalogach systemów (patrz zasada o dart:io
/// w testach widgetowych). Foldery spoza [knownFolderKeys] i pliki luzem
/// lądują w [DeviceIndex.unknown].
DeviceIndex scanDevice(StorageSettings settings, Iterable<String> systemCodes,
    Set<String> knownFolderKeys) {
  final games = <String, Map<String, Map<String, int>>>{};
  final unknown = <UnknownEntry>[];
  for (final code in systemCodes) {
    final dir = Directory(settings.dirFor(code));
    if (!dir.existsSync()) continue;
    for (final e in dir.listSync()) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is File) {
        unknown.add(UnknownEntry(systemCode: code, path: e.path, bytes: e.lengthSync(), isDirectory: false));
      } else if (e is Directory) {
        final sizes = _sizesUnder(e);
        if (knownFolderKeys.contains('$code/$name')) {
          games.putIfAbsent(code, () => {})[name] = sizes;
        } else {
          unknown.add(UnknownEntry(systemCode: code, path: e.path,
              bytes: sizes.values.fold(0, (a, b) => a + b), isDirectory: true));
        }
      }
    }
  }
  return DeviceIndex(games: games, unknown: unknown);
}

Map<int, LocalGameState> buildLocalStates(
    List<ManifestEntry> manifest, DeviceIndex index, StorageSettings settings) => {
      for (final entry in manifest)
        entry.gameId: diffGame(
          entry.files,
          index.games[entry.systemCode]?[entry.folder] ?? const {},
          settings,
          entry.systemCode,
          entry.folder,
        ),
    };
```

Usuń `local_scanner.dart` (jego test też). `download_manager.dart`: `settings.pathFor(game.systemCode, game.folder, file.name)` i `buildTask(..., folder: game.folder)`.

- [ ] **Step 4: Testy**

Run: `cd app && flutter analyze && timeout 600 flutter test`
Expected: testy `core` zielone; testy `features` mogą jeszcze nie kompilować się przez `localStateProvider` (Task 7 je przepisuje) — jeśli tak, uruchom tylko `test/core` i zacommituj; bramkę pokrycia domyka Task 7.

- [ ] **Step 5: Commit**

```bash
git add app
git commit -m "feat(app): ścieżki z folderem gry i jednoprzebiegowy skan urządzenia"
```

---

### Task 7: Providery — indeks urządzenia zamiast zapytań per gra

**Files:**
- Modify: `app/lib/features/library/providers.dart`, `app/lib/features/game/providers.dart`, `app/lib/features/game/delete_dialog.dart`, `app/lib/core/downloads/download_manager.dart` (`downloadManagerProvider.onGameChanged`), `app/lib/features/library/widgets/install_badge.dart`
- Test: `app/test/features/shelves_test.dart`, `home_screen_test.dart`, `system_screen_test.dart`, `library_widgets_test.dart`, `game_detail_test.dart`, `game_actions_test.dart`, `download_flow_test.dart`, `router_test.dart`, `downloads_screen_test.dart`, nowy `device_index_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class DeviceIndexController extends AsyncNotifier<Map<int, LocalGameState>> {
    @override Future<Map<int, LocalGameState>> build();   // czeka na snapshot + settings, skanuje
    Future<void> refresh();                                 // ponowny skan bez sieci
  }
  final deviceIndexProvider = AsyncNotifierProvider<DeviceIndexController, Map<int, LocalGameState>>(...);
  final unknownOnDeviceProvider = Provider<List<UnknownEntry>>(...);   // z ostatniego skanu
  final localStateProvider = FutureProvider.family<LocalGameState, int>(
      (ref, id) async => (await ref.watch(deviceIndexProvider.future))[id] ?? kNotInstalled);
  final installedIdsProvider = Provider<Set<int>>(...);   // status != none
  final updatableIdsProvider = Provider<Set<int>>(...);   // updateAvailable
  const kNotInstalled = LocalGameState(status: InstallStatus.none, updateAvailable: false, missing: [], presentPaths: []);
  ```
  `IdSet` znika. `InstallBadge` tylko wyświetla. `downloadManagerProvider`: `onGameChanged: (_) => ref.read(deviceIndexProvider.notifier).refresh()`. `confirmAndDelete`: po usunięciu plików usuwa pusty katalog gry (`Directory(settings.gameDir(...))` gdy `listSync().isEmpty`), potem `refresh()`; sygnatura `confirmAndDelete(context, ref, GameDetail game, LocalGameState local)`.
- `localStateProvider(id)` pozostaje `FutureProvider.family`, więc istniejące nadpisania `overrideWith((ref) async => state)` w testach dalej działają. Testy, które wołały `installedIdsProvider.notifier.mark(...)`, nadpisują teraz `deviceIndexProvider.overrideWith(() => FakeDeviceIndex({id: state}))` — dodaj w `test/fakes/fake_device_index.dart`:
  ```dart
  class FakeDeviceIndex extends DeviceIndexController {
    FakeDeviceIndex(this.states);
    final Map<int, LocalGameState> states;
    @override Future<Map<int, LocalGameState>> build() async => states;
    @override Future<void> refresh() async => state = AsyncData(states);
  }
  ```

- [ ] **Step 1: Testy**

`device_index_test.dart` (ProviderContainer, katalog tymczasowy, `storageSettingsProvider` nadpisany na `StorageSettings(tmp)`, `librarySnapshotProvider` nadpisany snapshotem z manifestem 2 gier): po `await container.read(deviceIndexProvider.future)` mapa ma stan `installed` dla gry, której plik leży w `tmp/snes/Mario (USA)/`; `installedIdsProvider == {1}`; `unknownOnDeviceProvider` zawiera folder `tmp/snes/Other`; po dopisaniu drugiego pliku i `refresh()` mapa się zmienia; `localStateProvider(99)` (brak w manifeście) → `kNotInstalled`.

Przepisz istniejące testy:
- `shelves_test.dart` `providers derive from the snapshot`: zamiast `mark` → override `deviceIndexProvider` przez `FakeDeviceIndex({3: installedState})`.
- `home_screen_test.dart` „installed shelf appears" i „stable keys": override `deviceIndexProvider` zamiast `localStateProvider(2)`/`mark`.
- `system_screen_test.dart` chipy: override `deviceIndexProvider` mapą stanów 1–3.
- `library_widgets_test.dart` `InstallBadge reflects state and feeds id sets` → tylko „reflects state" (usuń asercje na zbiorach; zbiory testuje `device_index_test`).
- `game_detail_test.dart`, `game_actions_test.dart`, `download_flow_test.dart`, `router_test.dart`: `GameDetail` z `folder`; `confirmAndDelete` z `game`; test usuwania sprawdza, że pusty katalog gry znika, a katalog z innym plikiem (np. `save.srm`) zostaje.
- `downloads_screen_test.dart`: `GameSummary` w `CoverThumb` — bez zmian poza `folder`.

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd app && timeout 300 flutter test test/features/device_index_test.dart`

- [ ] **Step 3: Implementacja**

```dart
// features/library/providers.dart — dopisz
class DeviceIndexController extends AsyncNotifier<Map<int, LocalGameState>> {
  DeviceIndex _last = const DeviceIndex(games: {}, unknown: []);
  DeviceIndex get lastIndex => _last;

  @override
  Future<Map<int, LocalGameState>> build() async {
    final snapshot = await ref.watch(librarySnapshotProvider.future);
    final settings = await ref.watch(storageSettingsProvider.future);
    return _compute(snapshot, settings);
  }

  Map<int, LocalGameState> _compute(LibrarySnapshot snapshot, StorageSettings settings) {
    final known = {for (final e in snapshot.manifest) '${e.systemCode}/${e.folder}'};
    _last = scanDevice(settings, [for (final s in snapshot.systems) s.code], known);
    return buildLocalStates(snapshot.manifest, _last, settings);
  }

  /// Ponowny skan dysku po pobraniu/usunięciu — bez sieci.
  Future<void> refresh() async {
    final snapshot = ref.read(librarySnapshotProvider).value;
    final settings = ref.read(storageSettingsProvider).value;
    if (snapshot == null || settings == null) return;
    state = AsyncData(_compute(snapshot, settings));
  }
}

final deviceIndexProvider =
    AsyncNotifierProvider<DeviceIndexController, Map<int, LocalGameState>>(DeviceIndexController.new);

final unknownOnDeviceProvider = Provider<List<UnknownEntry>>((ref) {
  ref.watch(deviceIndexProvider); // przelicz po każdym skanie
  return ref.read(deviceIndexProvider.notifier).lastIndex.unknown;
});

final installedIdsProvider = Provider<Set<int>>((ref) {
  final states = ref.watch(deviceIndexProvider).value ?? const {};
  return {for (final e in states.entries) if (e.value.status != InstallStatus.none) e.key};
});

final updatableIdsProvider = Provider<Set<int>>((ref) {
  final states = ref.watch(deviceIndexProvider).value ?? const {};
  return {for (final e in states.entries) if (e.value.updateAvailable) e.key};
});
```

`features/game/providers.dart`: `localStateProvider` jak w Interfaces (import `kNotInstalled` z `local_state.dart`, gdzie go zdefiniuj). `delete_dialog.dart`:

```dart
Future<void> deleteLocalFiles(List<String> presentPaths, {String? gameDir}) async {
  for (final path in presentPaths) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
  if (gameDir != null) {
    final dir = Directory(gameDir);
    if (dir.existsSync() && dir.listSync().isEmpty) dir.deleteSync();
  }
}

Future<bool> confirmAndDelete(BuildContext context, WidgetRef ref, GameDetail game, LocalGameState local) async {
  // dialog jak dziś
  final settings = await ref.read(storageSettingsProvider.future);
  await deleteLocalFiles(local.presentPaths, gameDir: settings.gameDir(game.systemCode, game.folder));
  await ref.read(deviceIndexProvider.notifier).refresh();
  return true;
}
```

`install_badge.dart`: usuń blok z notatnikami; zostaje odczyt `localStateProvider(gameId)` i rysowanie. `download_manager.dart`: `onGameChanged: (_) => ref.read(deviceIndexProvider.notifier).refresh()`. `game_detail_screen.dart`: wywołanie `confirmAndDelete(context, ref, game, state)`. `settings_screen.dart`: po zapisie katalogu/Wi‑Fi już invaliduje `storageSettingsProvider` (indeks przelicza się przez zależność w `build`).

- [ ] **Step 4: Testy i bramka**

Run: `cd app && flutter analyze && timeout 600 flutter test && cd .. && ./scripts/check_coverage_app.sh`
Expected: PASS, 100%. Upewnij się, że żadna odznaka ani ekran nie czyta już `gameDetailProvider` poza kartą gry (`grep -rn gameDetailProvider app/lib`).

- [ ] **Step 5: Commit**

```bash
git add app
git commit -m "feat(app): indeks urządzenia zasila stan gier, filtry i półki bez zapytań per gra"
```

---

### Task 8: Ustawienia — „Nieznane na urządzeniu"

**Files:**
- Modify: `app/lib/features/settings/settings_screen.dart`
- Test: `app/test/features/settings_test.dart`

**Interfaces:**
- Consumes: `unknownOnDeviceProvider`, `deviceIndexProvider.notifier.refresh()`, `storageSettingsProvider`, `formatBytes`, `SettingsRow`, `GlassPanel`.
- Produces: w karcie „Urządzenie" wiersz `SettingsRow(key: Key('unknown-on-device'), title: 'Nieznane na urządzeniu', subtitle: 'N pozycji · X' / 'Brak', trailing: chevron gdy N>0, onTap → dialog)`. Dialog `AlertDialog(title: 'Nieznane na urządzeniu')` z listą ścieżek względem `baseDir` (max 50 wierszy, potem `… i N więcej`), przyciski `Zamknij` i `Usuń wszystko` (`Key('unknown-delete-all')`). Usuwanie: pure funkcja `deleteUnknown(List<UnknownEntry>, String baseDir)` — kasuje tylko ścieżki zaczynające się od `baseDir/` (pliki `deleteSync`, katalogi `deleteSync(recursive: true)`), potem `refresh()`.

- [ ] **Step 1: Testy**

W `settings_test.dart` dopisz (helper `_screen` dostaje override `deviceIndexProvider` przez `FakeDeviceIndex` z ustawionym `lastIndex`; rozszerz `FakeDeviceIndex` o opcjonalny parametr `unknown` i nadpisanie `lastIndex`):

```dart
  testWidgets('unknown-on-device row shows count and deletes on request', (tester) async {
    final root = Directory.systemTemp.createTempSync('roms');
    addTearDown(() => root.deleteSync(recursive: true));
    final stray = File('${root.path}/snes/old.sfc')..createSync(recursive: true)..writeAsBytesSync([1, 2]);
    final strayDir = Directory('${root.path}/snes/Old Game')..createSync(recursive: true);
    File('${strayDir.path}/x.sfc').writeAsBytesSync([1, 2, 3]);
    final unknown = [
      UnknownEntry(systemCode: 'snes', path: stray.path, bytes: 2, isDirectory: false),
      UnknownEntry(systemCode: 'snes', path: strayDir.path, bytes: 3, isDirectory: true),
    ];
    await tester.pumpWidget(_screen(repo: await _signedIn(), baseDir: root.path, unknown: unknown));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('unknown-on-device')), 200);
    expect(find.text('2 pozycje · 5 B'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unknown-on-device')));
    await tester.pumpAndSettle();
    expect(find.text('snes/old.sfc'), findsOneWidget);
    expect(find.text('snes/Old Game'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unknown-delete-all')));
    await tester.pumpAndSettle();
    expect(stray.existsSync(), isFalse);
    expect(strayDir.existsSync(), isFalse);
  });

  testWidgets('no unknown entries shows Brak and opens nothing', (tester) async {
    await tester.pumpWidget(_screen(repo: await _signedIn()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('unknown-on-device')), 200);
    expect(find.text('Brak'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unknown-on-device')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  test('deleteUnknown refuses paths outside the base dir', () {
    final root = Directory.systemTemp.createTempSync('roms');
    addTearDown(() => root.deleteSync(recursive: true));
    final outside = File('${Directory.systemTemp.path}/droplet-outside-${root.hashCode}.tmp')..writeAsBytesSync([1]);
    addTearDown(() { if (outside.existsSync()) outside.deleteSync(); });
    deleteUnknown([UnknownEntry(systemCode: 'x', path: outside.path, bytes: 1, isDirectory: false)], root.path);
    expect(outside.existsSync(), isTrue);
  });
```

Polska liczebność: `1 pozycja`, `2–4 pozycje`, `5+ pozycji` — dodaj małą funkcję `pluralPositions(int)` z testem (1, 2, 5, 22, 25).

- [ ] **Step 2: Uruchom — FAIL**

Run: `cd app && timeout 300 flutter test test/features/settings_test.dart`

- [ ] **Step 3: Implementacja**

W `_DeviceCard` dodaj po wierszu wolnego miejsca:

```dart
          const _Divider(),
          _UnknownRow(baseDir: baseDir),
```

```dart
String pluralPositions(int n) => switch (n % 10) {
      1 when n % 100 != 11 => '$n pozycja',
      2 || 3 || 4 when n % 100 < 10 || n % 100 > 20 => '$n pozycje',
      _ => '$n pozycji',
    };

/// Usuwa tylko wpisy leżące pod [baseDir] — nic poza katalogiem ROMów.
void deleteUnknown(List<UnknownEntry> entries, String baseDir) {
  for (final e in entries) {
    if (!e.path.startsWith('$baseDir/')) continue;
    if (e.isDirectory) {
      final d = Directory(e.path);
      if (d.existsSync()) d.deleteSync(recursive: true);
    } else {
      final f = File(e.path);
      if (f.existsSync()) f.deleteSync();
    }
  }
}

class _UnknownRow extends ConsumerWidget {
  const _UnknownRow({required this.baseDir});
  final String? baseDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unknown = ref.watch(unknownOnDeviceProvider);
    final bytes = unknown.fold(0, (a, e) => a + e.bytes);
    return SettingsRow(
      key: const Key('unknown-on-device'),
      title: 'Nieznane na urządzeniu',
      subtitle: unknown.isEmpty ? 'Brak' : '${pluralPositions(unknown.length)} · ${formatBytes(bytes)}',
      trailing: unknown.isEmpty ? null : const Icon(Icons.chevron_right, color: kTextDim),
      onTap: unknown.isEmpty || baseDir == null ? null : () => _showUnknown(context, ref, unknown, baseDir!),
    );
  }

  Future<void> _showUnknown(BuildContext context, WidgetRef ref, List<UnknownEntry> unknown, String baseDir) async {
    final shown = unknown.take(50).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nieznane na urządzeniu'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in shown)
                Text(e.path.substring(baseDir.length + 1), style: const TextStyle(color: kTextDim, fontSize: 13)),
              if (unknown.length > shown.length)
                Text('… i ${unknown.length - shown.length} więcej', style: const TextStyle(color: kTextDim, fontSize: 13)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Zamknij')),
          TextButton(
            key: const Key('unknown-delete-all'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Usuń wszystko'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    deleteUnknown(unknown, baseDir);
    await ref.read(deviceIndexProvider.notifier).refresh();
  }
}
```

(`shrinkWrap` w dialogu z ≤ 51 wierszami tekstu jest w porządku — to nie jest lista okładek.)

- [ ] **Step 4: Testy i bramka**

Run: `cd app && flutter analyze && timeout 600 flutter test && cd .. && ./scripts/check_coverage_app.sh`

- [ ] **Step 5: Commit**

```bash
git add app
git commit -m "feat(settings): nieznane pliki i foldery na urządzeniu z opcją usunięcia"
```

---

### Task 9: E2E, wersja, dokumentacja, lokalna biblioteka Jana

**Files:**
- Modify: `app/integration_test/download_flow_test.dart`, `app/integration_test/app_flow_test.dart` (jeśli dotyka ścieżek)
- Modify: `app/pubspec.yaml` (`version: 0.3.0+3`), `app/lib/features/settings/settings_screen.dart` (`appVersion = '0.3.0'`)
- Modify: `RALPH-STATUS.md`, `docs/deploy.md` (układ biblioteki), `docs/superpowers/plans/2026-09-01-droplet-milestones.md` (M7)
- Move: `library/gbc/Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc` → `library/gbc/Pokemon - Crystal Version/…` (katalog `library/` jest poza gitem lub w nim — sprawdź `git status`; przenosiny wykonaj `mv`).

- [ ] **Step 1: E2E aplikacji**

W `download_flow_test.dart` ścieżka ROM-u: `'$baseDir/snes/Super Mario World (USA)/Super Mario World (USA).sfc'`; po `Usuń` dodatkowo `expect(Directory('$baseDir/snes/Super Mario World (USA)').existsSync(), isFalse)`. Fixture backendu z Task 4 ma już foldery.

- [ ] **Step 2: Wersja i dokumenty**

- `pubspec.yaml` `0.3.0+3`, `appVersion = '0.3.0'` (popraw test `Droplet $appVersion` — używa stałej, więc bez zmian).
- `docs/deploy.md`: sekcja „Układ biblioteki": `<biblioteka>/<system>/<Nazwa gry>/<pliki>`; pliki luzem widoczne w adminie pod „Do uporządkowania"; przykłady dla Switcha (base+UPD+DLC w jednym folderze) i PSX (m3u + cue/bin, podkatalogi dozwolone).
- `RALPH-STATUS.md`, „Czeka na Jana": „**M7 na NAS-ie**: uporządkuj bibliotekę (każda gra w folderze), `docker compose up -d --build` (migracja 0002), `manage.py scan`, przejrzyj `/admin/library/loosefile/`; w aplikacji 0.3.0 stare płaskie pliki pokażą się w Ustawienia → Nieznane na urządzeniu." Usuń wpis o ograniczeniu filtrów zasilanych odznakami (naprawione przez indeks urządzenia).
- `2026-09-01-droplet-milestones.md`: sekcja M7 z linkiem do specu i planu.

- [ ] **Step 3: Lokalna biblioteka i backend Jana**

```bash
cd /Users/johniak/Projects/droplet
mkdir -p "library/gbc/Pokemon - Crystal Version" && mv "library/gbc/Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc" "library/gbc/Pokemon - Crystal Version/"
export LIBRARY_PATH="$PWD/library" DJANGO_SECRET_KEY=dev-secret DROPLET_ADMIN_USER=jan DROPLET_ADMIN_PASSWORD=droplet
docker compose up -d --build && sleep 5 && docker compose exec -T web python manage.py scan
```

Sprawdź `curl -s -H "Authorization: Token <token>" localhost:8000/api/manifest/` → jedna gra z `folder == "Pokemon - Crystal Version"`.

- [ ] **Step 4: Bramki i e2e**

Run: `cd backend && pytest -q && cd .. && ./scripts/check_coverage_app.sh && cd app && flutter analyze && cd .. && ./scripts/e2e_backend.sh && E2E_SERVER=http://10.0.2.2:8800 ./scripts/e2e_app.sh`
Expected: wszystko zielone (e2e wymagają Dockera i emulatora; bez nich zapisz krok dla Jana zamiast udawać). Po e2e przywróć backend Jana na 8000 (`docker compose up -d`, bo skrypt e2e zdejmuje stos).

- [ ] **Step 5: Commit**

```bash
git add app RALPH-STATUS.md docs
git commit -m "test(e2e): ścieżki z folderem gry; wersja 0.3.0; dokumentacja układu biblioteki"
```

---

## Samokontrola planu względem specu

| Wymaganie | Task |
|---|---|
| `Game.folder`, `LooseFile`, `ScanRun.loose_files`, migracja z wypełnieniem | 1 |
| Folder = gra, role w katalogu, sidecar → other, pliki luzem | 2 |
| Sync po folderze, zamiana zbioru `LooseFile`, liczniki, legacy bez folderu | 3 |
| `folder` w API, `name` z podścieżką, `/api/manifest/`, fixture e2e | 4 |
| Admin: lista „Do uporządkowania", kolumna luzem, ScanRun | 1 |
| App: modele, `fetchManifest`, cache, snapshot | 5 |
| `gameDir/pathFor`, `buildTask` z podkatalogiem, `diffGame` z folderem, `scanDevice`, `buildLocalStates` | 6 |
| `deviceIndexProvider`, `unknownOnDeviceProvider`, pochodne zbiory, `localStateProvider` z mapy, wyzwalacze refresh, usuwanie z rmdir | 7 |
| „Nieznane na urządzeniu" z usuwaniem | 8 |
| E2E, wersja 0.3.0, docs, przeniesienie lokalnego ROM-u | 9 |
