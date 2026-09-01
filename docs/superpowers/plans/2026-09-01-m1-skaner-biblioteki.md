# M1 — Skaner biblioteki: plan implementacji

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backend zna całą kolekcję: systemy z katalogów 1. poziomu, gry pogrupowane z plików (cue/bin, m3u, Switch base/update/DLC), skan przyrostowy w tle, wszystko widoczne i poprawialne w Django admin.

**Architecture:** App `library` z modelami `System/Game/GameFile/ScanRun`; czysta logika (normalizacja nazw, parsery, grupowanie) w pakiecie `library/scanner/` bez zależności od ORM — testowalna na `tmp_path`; synchronizacja z DB w `library/scanner/scan.py`; wyzwalanie: task w tle, komenda `manage.py scan`, `POST /api/scan/`, nocny cron na TrueNAS.

**Tech Stack:** jak M0 (bez nowych zależności).

**Spec:** `docs/superpowers/specs/2026-09-01-droplet-design.md` (§3.2, §3.3)

## Global Constraints

- Obowiązują Global Constraints z planu M0 — w tym **pokrycie 100%** (`pytest --cov --cov-fail-under=100` przy zamykaniu każdego zadania) i **suita e2e** (`backend/e2e/` przez `scripts/e2e_backend.sh`).
- `/library` traktujemy jako **read-only** — skaner nigdy nie pisze do biblioteki.
- Tożsamość pliku: `relative_path` + `size` + `mtime_ns` (zero hashowania przy skanie).
- Identyczność gry: `(system, normalized_title)`; dla Switcha dodatkowo scala po title-id (prefiks 12 hex).
- Skan przyrostowy i idempotentny: drugi bieg bez zmian na dysku = zero zapisów poza `ScanRun`.
- Błąd pojedynczego pliku/katalogu trafia do `ScanRun.errors`, nie przerywa skanu.
- Biegi częściowe (`pytest <plik>`) z `--no-cov`; bramka = pełny `pytest`. Testy API używają fixture `auth_client` z `backend/conftest.py` (M0 Task 7a).

---

### Task 1: Modele System/Game/GameFile/ScanRun + admin (podstawowy)

**Files:**
- Create: `backend/library/__init__.py`, `backend/library/apps.py`, `backend/library/models.py`, `backend/library/admin.py`, `backend/library/tests/__init__.py`, `backend/library/migrations/` (via makemigrations)
- Modify: `backend/droplet/settings.py` (INSTALLED_APPS += `"library"`)
- Test: `backend/library/tests/test_models.py`

**Interfaces:**
- Produces (używane przez wszystkie kolejne taski i M2/M3):

```python
class System(models.Model):
    code = models.SlugField(unique=True)            # "snes"
    name = models.CharField(max_length=200)          # "Super Nintendo"
    directory = models.CharField(max_length=255, unique=True)  # katalog w /library
    thumbnail_repo = models.CharField(max_length=255, blank=True)  # repo libretro-thumbnails
    needs_config = models.BooleanField(default=False)
    sort_order = models.IntegerField(default=0)

class Game(models.Model):
    system = models.ForeignKey(System, on_delete=models.CASCADE, related_name="games")
    title = models.CharField(max_length=500)             # do wyświetlania
    normalized_title = models.CharField(max_length=500, db_index=True)
    switch_title_prefix = models.CharField(max_length=12, blank=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    class Meta:
        constraints = [models.UniqueConstraint(fields=["system", "normalized_title"], name="uniq_game_per_system")]

class GameFile(models.Model):
    class Role(models.TextChoices):
        BASE = "base"; UPDATE = "update"; DLC = "dlc"
        DISC = "disc"; SUPPORT = "support"; OTHER = "other"
    game = models.ForeignKey(Game, on_delete=models.CASCADE, related_name="files")
    relative_path = models.CharField(max_length=1000, unique=True)
    role = models.CharField(max_length=10, choices=Role.choices, default=Role.BASE)
    disc_number = models.PositiveIntegerField(null=True, blank=True)
    version = models.CharField(max_length=50, blank=True)
    size = models.BigIntegerField()
    mtime_ns = models.BigIntegerField()

class ScanRun(models.Model):
    class Status(models.TextChoices):
        RUNNING = "running"; SUCCESS = "success"; FAILED = "failed"
    started_at = models.DateTimeField(auto_now_add=True)
    finished_at = models.DateTimeField(null=True, blank=True)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.RUNNING)
    games_created = models.IntegerField(default=0)
    files_created = models.IntegerField(default=0)
    files_updated = models.IntegerField(default=0)
    files_deleted = models.IntegerField(default=0)
    errors = models.JSONField(default=list)
```

- [x] **Step 1: Failing test**

`backend/library/tests/test_models.py`:

```python
import pytest
from django.db import IntegrityError

from library.models import Game, GameFile, System


@pytest.mark.django_db
def test_game_unique_per_system():
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    Game.objects.create(system=s, title="Mario", normalized_title="mario")
    with pytest.raises(IntegrityError):
        Game.objects.create(system=s, title="Mario 2", normalized_title="mario")


@pytest.mark.django_db
def test_gamefile_path_unique():
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    GameFile.objects.create(game=g, relative_path="snes/mario.sfc", size=1, mtime_ns=1)
    with pytest.raises(IntegrityError):
        GameFile.objects.create(game=g, relative_path="snes/mario.sfc", size=2, mtime_ns=2)
```

- [x] **Step 2: Uruchom — FAIL** (`pytest library -v` → import errors)

- [x] **Step 3: Implementacja** — `startapp library`, modele jak w Interfaces, `INSTALLED_APPS += ["library"]`, `python manage.py makemigrations library`. W `library/admin.py` na razie proste rejestracje:

```python
from django.contrib import admin

from .models import Game, GameFile, ScanRun, System

admin.site.register(System)
admin.site.register(Game)
admin.site.register(GameFile)
admin.site.register(ScanRun)
```

- [x] **Step 4: Testy zielone** — `pytest library -v` PASS.

- [x] **Step 5: Commit** — `git add backend/library backend/droplet/settings.py && git commit -m "feat: library models for systems, games, files and scan runs"`

---

### Task 2: Normalizacja tytułów (`naming.py`)

**Files:**
- Create: `backend/library/scanner/__init__.py`, `backend/library/scanner/naming.py`
- Test: `backend/library/tests/test_naming.py`

**Interfaces:**
- Produces:
  - `display_title(stem: str) -> str` — zdejmuje tagi `(...)`/`[...]`, poprawia `"Zelda, The"` → `"The Zelda"`, trymuje spacje.
  - `normalize_title(stem: str) -> str` — `display_title` → lowercase → tylko `[a-z0-9 ]`, pojedyncze spacje. Używane jako klucz gry i do dopasowań okładek (M2).

- [x] **Step 1: Failing testy**

`backend/library/tests/test_naming.py`:

```python
import pytest

from library.scanner.naming import display_title, normalize_title


@pytest.mark.parametrize(
    "stem,expected",
    [
        ("Super Mario World (USA)", "Super Mario World"),
        ("Legend of Zelda, The (USA) (Rev A) [!]", "The Legend of Zelda"),
        ("Final Fantasy VII (Europe) (Disc 1)", "Final Fantasy VII"),
        ("  Metroid   Prime  ", "Metroid Prime"),
    ],
)
def test_display_title(stem, expected):
    assert display_title(stem) == expected


@pytest.mark.parametrize(
    "stem,expected",
    [
        ("Super Mario World (USA)", "super mario world"),
        ("R-Type III (USA)", "r type iii"),
        ("Pokémon - Édition Rouge (France)", "pokemon edition rouge"),
    ],
)
def test_normalize_title(stem, expected):
    assert normalize_title(stem) == expected
```

- [x] **Step 2: FAIL** — `pytest library/tests/test_naming.py -v`

- [x] **Step 3: Implementacja**

`backend/library/scanner/naming.py`:

```python
import re
import unicodedata

_TAGS = re.compile(r"[\(\[][^\)\]]*[\)\]]")
_ARTICLE = re.compile(r"^(?P<t>.+), (?P<a>The|A|An|Le|La|Les|Der|Die|Das)$")


def display_title(stem: str) -> str:
    s = _TAGS.sub(" ", stem)
    s = re.sub(r"\s+", " ", s).strip(" -_.")
    m = _ARTICLE.match(s)
    if m:
        s = f"{m.group('a')} {m.group('t')}"
    return s


def normalize_title(stem: str) -> str:
    s = display_title(stem)
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-z0-9]+", " ", s.lower())
    return re.sub(r"\s+", " ", s).strip()
```

- [x] **Step 4: PASS** — `pytest library/tests/test_naming.py -v`

- [x] **Step 5: Commit** — `git add backend/library/scanner backend/library/tests/test_naming.py && git commit -m "feat: title normalization for grouping and matching"`

---

### Task 3: Parser tagów Switcha

**Files:**
- Create: `backend/library/scanner/switch.py`
- Test: `backend/library/tests/test_switch.py`

**Interfaces:**
- Produces:

```python
@dataclass(frozen=True)
class SwitchInfo:
    title_id: str | None   # 16 hex albo None
    role: str              # GameFile.Role: "base" | "update" | "dlc"
    version: str           # np. "v1.2.0" / "v131072" / ""
parse_switch(stem: str) -> SwitchInfo
title_prefix(title_id: str) -> str  # pierwsze 12 hex — wspólne dla base/UPD/DLC
```

- [x] **Step 1: Failing testy**

`backend/library/tests/test_switch.py`:

```python
import pytest

from library.scanner.switch import parse_switch, title_prefix


@pytest.mark.parametrize(
    "stem,tid,role,version",
    [
        ("Hollow Knight [0100633007D48000][v0]", "0100633007D48000", "base", "v0"),
        ("Hollow Knight [UPD][0100633007D48800][v196608]", "0100633007D48800", "update", "v196608"),
        ("Hollow Knight - Voidheart [DLC][0100633007D49001]", "0100633007D49001", "dlc", ""),
        ("Celeste (UPD) (v1.2.6)", None, "update", "v1.2.6"),
        ("Celeste", None, "base", ""),
    ],
)
def test_parse_switch(stem, tid, role, version):
    info = parse_switch(stem)
    assert (info.title_id, info.role, info.version) == (tid, role, version)


def test_title_prefix_groups_family():
    assert title_prefix("0100633007D48000") == title_prefix("0100633007D48800")
```

- [x] **Step 2: FAIL** — `pytest library/tests/test_switch.py -v`

- [x] **Step 3: Implementacja**

`backend/library/scanner/switch.py`:

```python
import re
from dataclasses import dataclass

_TID = re.compile(r"[\[\(]([0-9A-Fa-f]{16})[\]\)]")
_VER = re.compile(r"[\[\(](v[\d.]+)[\]\)]", re.IGNORECASE)
_UPD = re.compile(r"[\[\(](UPD|UPDATE)[\]\)]", re.IGNORECASE)
_DLC = re.compile(r"[\[\(]DLC[\]\)]", re.IGNORECASE)


@dataclass(frozen=True)
class SwitchInfo:
    title_id: str | None
    role: str
    version: str


def title_prefix(title_id: str) -> str:
    return title_id.upper()[:12]


def parse_switch(stem: str) -> SwitchInfo:
    tid_m = _TID.search(stem)
    tid = tid_m.group(1).upper() if tid_m else None
    ver_m = _VER.search(stem)
    version = ver_m.group(1) if ver_m else ""
    if _DLC.search(stem):
        role = "dlc"
    elif _UPD.search(stem) or (tid and tid.endswith("800")):
        role = "update"
    else:
        role = "base"
    return SwitchInfo(title_id=tid, role=role, version=version)
```

- [x] **Step 4: PASS**, **Step 5: Commit** — `git add ... && git commit -m "feat: switch filename tag parser"`

---

### Task 4: Parsery cue i m3u

**Files:**
- Create: `backend/library/scanner/playlists.py`
- Test: `backend/library/tests/test_playlists.py`

**Interfaces:**
- Produces:
  - `parse_cue(text: str) -> list[str]` — nazwy plików z linii `FILE "..." BINARY`.
  - `parse_m3u(text: str) -> list[str]` — niepuste linie bez komentarzy `#`, kolejność = numer płyty.

- [x] **Step 1: Failing testy**

`backend/library/tests/test_playlists.py`:

```python
from library.scanner.playlists import parse_cue, parse_m3u

CUE = '''REM COMMENT
FILE "Game (Track 1).bin" BINARY
  TRACK 01 MODE2/2352
FILE "Game (Track 2).bin" BINARY
'''

M3U = """# playlist
Game (Disc 1).cue

Game (Disc 2).cue
"""


def test_parse_cue():
    assert parse_cue(CUE) == ["Game (Track 1).bin", "Game (Track 2).bin"]


def test_parse_m3u():
    assert parse_m3u(M3U) == ["Game (Disc 1).cue", "Game (Disc 2).cue"]
```

- [x] **Step 2: FAIL**

- [x] **Step 3: Implementacja**

`backend/library/scanner/playlists.py`:

```python
import re

_FILE = re.compile(r'^\s*FILE\s+"([^"]+)"', re.MULTILINE)


def parse_cue(text: str) -> list[str]:
    return _FILE.findall(text)


def parse_m3u(text: str) -> list[str]:
    return [
        line.strip()
        for line in text.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
```

- [x] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: cue and m3u parsers"`

---

### Task 5: Grupowanie katalogu systemu w gry

**Files:**
- Create: `backend/library/scanner/grouping.py`
- Test: `backend/library/tests/test_grouping.py`

**Interfaces:**
- Produces:

```python
@dataclass
class FileEntry:
    relative_path: str      # względem LIBRARY_ROOT, separator "/"
    role: str               # GameFile.Role
    disc_number: int | None
    version: str
    size: int
    mtime_ns: int

@dataclass
class GameGroup:
    title: str
    normalized_title: str
    switch_title_prefix: str          # "" poza Switchem
    files: list[FileEntry]

group_system_dir(system_dir: Path, library_root: Path, *, is_switch: bool) -> list[GameGroup]
```

Algorytm (dokładnie tak implementować):
1. Zbierz rekurencyjnie wszystkie pliki (pomiń ukryte `.*`).
2. Przeczytaj `.m3u`: każda pozycja playlisty (ścieżki względem pliku m3u) → rola `disc` z `disc_number` wg kolejności; sam `.m3u` → rola `support`; wszystko w jednej grze o tytule z nazwy m3u.
3. Przeczytaj `.cue` nienależące do m3u: cue → rola `base`, wskazywane biny → `support`, jedna gra z nazwy cue. Cue należące do m3u: cue → już `disc` (krok 2), jego biny → `support` tej samej gry.
4. Jeśli `is_switch`: pliki grupuj po `title_prefix(title_id)`; bez title-id — po `normalize_title`; role/wersje z `parse_switch`; tytuł gry z pliku `base` (fallback: pierwszy plik).
5. Pozostałe pliki: 1 plik = 1 gra, rola `base`.
6. Pliki już przypisane w krokach 2–4 nie wracają w kroku 5.

- [x] **Step 1: Failing testy**

`backend/library/tests/test_grouping.py`:

```python
import pytest

from library.scanner.grouping import group_system_dir


def _write(p, content=b"x"):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(content)


def _by_title(groups):
    return {g.title: g for g in groups}


def test_single_files_become_games(tmp_path):
    root = tmp_path
    _write(root / "snes" / "Super Mario World (USA).sfc")
    _write(root / "snes" / "F-Zero (USA).sfc")
    groups = group_system_dir(root / "snes", root, is_switch=False)
    assert len(groups) == 2
    g = _by_title(groups)["Super Mario World"]
    assert g.files[0].relative_path == "snes/Super Mario World (USA).sfc"
    assert g.files[0].role == "base"


def test_cue_bin_is_one_game(tmp_path):
    root = tmp_path
    _write(
        root / "psx" / "Tekken (USA).cue",
        b'FILE "Tekken (USA).bin" BINARY\n',
    )
    _write(root / "psx" / "Tekken (USA).bin")
    groups = group_system_dir(root / "psx", root, is_switch=False)
    assert len(groups) == 1
    roles = {f.relative_path.split("/")[-1]: f.role for f in groups[0].files}
    assert roles == {"Tekken (USA).cue": "base", "Tekken (USA).bin": "support"}


def test_m3u_multidisc(tmp_path):
    root = tmp_path
    d = root / "psx"
    _write(d / "FF7 (Disc 1).cue", b'FILE "FF7 (Disc 1).bin" BINARY\n')
    _write(d / "FF7 (Disc 1).bin")
    _write(d / "FF7 (Disc 2).cue", b'FILE "FF7 (Disc 2).bin" BINARY\n')
    _write(d / "FF7 (Disc 2).bin")
    _write(d / "FF7.m3u", b"FF7 (Disc 1).cue\nFF7 (Disc 2).cue\n")
    groups = group_system_dir(d, root, is_switch=False)
    assert len(groups) == 1
    discs = sorted(
        (f.disc_number, f.relative_path.split("/")[-1])
        for f in groups[0].files
        if f.role == "disc"
    )
    assert discs == [(1, "FF7 (Disc 1).cue"), (2, "FF7 (Disc 2).cue")]


def test_switch_family_grouped(tmp_path):
    root = tmp_path
    d = root / "switch"
    _write(d / "Hollow Knight [0100633007D48000][v0].nsp")
    _write(d / "Hollow Knight [UPD][0100633007D48800][v196608].nsp")
    _write(d / "Hollow Knight [DLC][0100633007D49001].nsp")
    _write(d / "Celeste [01002B30028F6000][v0].nsp")
    groups = group_system_dir(d, root, is_switch=True)
    assert len(groups) == 2
    hk = _by_title(groups)["Hollow Knight"]
    assert sorted(f.role for f in hk.files) == ["base", "dlc", "update"]
    upd = next(f for f in hk.files if f.role == "update")
    assert upd.version == "v196608"


def test_hidden_files_skipped(tmp_path):
    root = tmp_path
    _write(root / "snes" / ".DS_Store")
    assert group_system_dir(root / "snes", root, is_switch=False) == []


def test_m3u_missing_entry_is_skipped(tmp_path):
    root = tmp_path
    d = root / "psx"
    _write(d / "FF7 (Disc 1).cue", b'FILE "FF7 (Disc 1).bin" BINARY\n')
    _write(d / "FF7 (Disc 1).bin")
    _write(d / "FF7.m3u", b"FF7 (Disc 1).cue\nFF7 (Disc 2).cue\n")  # Disc 2 nie istnieje
    groups = group_system_dir(d, root, is_switch=False)
    assert len(groups) == 1
    assert [f.disc_number for f in groups[0].files if f.role == "disc"] == [1]


def test_switch_without_title_id_groups_by_title(tmp_path):
    root = tmp_path
    d = root / "switch"
    _write(d / "Celeste.nsp")
    _write(d / "Celeste (UPD) (v1.2.6).nsp")
    groups = group_system_dir(d, root, is_switch=True)
    assert len(groups) == 1
    assert sorted(f.role for f in groups[0].files) == ["base", "update"]
```

- [x] **Step 2: FAIL** — `pytest library/tests/test_grouping.py -v`

- [x] **Step 3: Implementacja**

`backend/library/scanner/grouping.py`:

```python
from dataclasses import dataclass, field
from pathlib import Path

from .naming import display_title, normalize_title
from .playlists import parse_cue, parse_m3u
from .switch import parse_switch, title_prefix


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
    title: str
    normalized_title: str
    switch_title_prefix: str = ""
    files: list[FileEntry] = field(default_factory=list)


def _entry(path: Path, root: Path, role: str, disc=None, version="") -> FileEntry:
    st = path.stat()
    return FileEntry(
        relative_path=path.relative_to(root).as_posix(),
        role=role,
        disc_number=disc,
        version=version,
        size=st.st_size,
        mtime_ns=st.st_mtime_ns,
    )


def group_system_dir(system_dir: Path, library_root: Path, *, is_switch: bool) -> list[GameGroup]:
    all_files = sorted(
        p for p in system_dir.rglob("*")
        if p.is_file() and not any(part.startswith(".") for part in p.parts)
    )
    file_set = set(all_files)
    claimed: set[Path] = set()
    groups: list[GameGroup] = []

    def resolve(base: Path, name: str) -> Path | None:
        cand = base.parent / name
        return cand if cand in file_set else None

    # 1. m3u
    for m3u in [p for p in all_files if p.suffix.lower() == ".m3u"]:
        group = GameGroup(
            title=display_title(m3u.stem), normalized_title=normalize_title(m3u.stem)
        )
        group.files.append(_entry(m3u, library_root, "support"))
        claimed.add(m3u)
        for i, name in enumerate(parse_m3u(m3u.read_text(errors="replace")), start=1):
            disc = resolve(m3u, name)
            if disc is None:
                continue
            group.files.append(_entry(disc, library_root, "disc", disc=i))
            claimed.add(disc)
            if disc.suffix.lower() == ".cue":
                for bin_name in parse_cue(disc.read_text(errors="replace")):
                    b = resolve(disc, bin_name)
                    if b is not None:
                        group.files.append(_entry(b, library_root, "support"))
                        claimed.add(b)
        groups.append(group)

    # 2. samotne cue
    for cue in [p for p in all_files if p.suffix.lower() == ".cue" and p not in claimed]:
        group = GameGroup(
            title=display_title(cue.stem), normalized_title=normalize_title(cue.stem)
        )
        group.files.append(_entry(cue, library_root, "base"))
        claimed.add(cue)
        for bin_name in parse_cue(cue.read_text(errors="replace")):
            b = resolve(cue, bin_name)
            if b is not None and b not in claimed:
                group.files.append(_entry(b, library_root, "support"))
                claimed.add(b)
        groups.append(group)

    rest = [p for p in all_files if p not in claimed]

    # 3. switch
    if is_switch:
        families: dict[str, GameGroup] = {}
        for p in rest:
            info = parse_switch(p.stem)
            key = title_prefix(info.title_id) if info.title_id else normalize_title(p.stem)
            group = families.setdefault(
                key,
                GameGroup(
                    title=display_title(p.stem),
                    normalized_title=normalize_title(p.stem),
                    switch_title_prefix=key if info.title_id else "",
                ),
            )
            if info.role == "base":
                group.title = display_title(p.stem)
                group.normalized_title = normalize_title(p.stem)
            group.files.append(_entry(p, library_root, info.role, version=info.version))
        groups.extend(families.values())
        return groups

    # 4. reszta: 1 plik = 1 gra
    for p in rest:
        groups.append(
            GameGroup(
                title=display_title(p.stem),
                normalized_title=normalize_title(p.stem),
                files=[_entry(p, library_root, "base")],
            )
        )
    return groups
```

- [x] **Step 4: PASS** — `pytest library/tests/test_grouping.py -v`

- [x] **Step 5: Commit** — `git commit -m "feat: group system directory files into game groups"`

---

### Task 6: Mapa katalogów → systemy

**Files:**
- Create: `backend/library/scanner/systems_map.py`
- Test: `backend/library/tests/test_systems_map.py`

**Interfaces:**
- Produces: `lookup_system(directory_name: str) -> SystemSpec | None`, gdzie `SystemSpec = dataclass(code, name, thumbnail_repo, is_switch: bool)`. Dopasowanie case-insensitive po nazwie katalogu i aliasach.

- [x] **Step 1: Failing testy**

`backend/library/tests/test_systems_map.py`:

```python
from library.scanner.systems_map import lookup_system


def test_full_retroarch_name():
    spec = lookup_system("Nintendo - Super Nintendo Entertainment System")
    assert spec.code == "snes"
    assert spec.thumbnail_repo == "Nintendo_-_Super_Nintendo_Entertainment_System"


def test_short_alias_case_insensitive():
    assert lookup_system("SNES").code == "snes"
    assert lookup_system("psx").code == "psx"


def test_switch_flag():
    assert lookup_system("switch").is_switch is True
    assert lookup_system("snes").is_switch is False


def test_unknown_returns_none():
    assert lookup_system("Losowy Katalog") is None
```

- [x] **Step 2: FAIL**

- [x] **Step 3: Implementacja**

`backend/library/scanner/systems_map.py` — dataclass + słownik. Wpisy minimum (rozszerzać w miarę potrzeb; `thumbnail_repo` = nazwa repo w github.com/libretro-thumbnails):

```python
from dataclasses import dataclass


@dataclass(frozen=True)
class SystemSpec:
    code: str
    name: str
    thumbnail_repo: str
    is_switch: bool = False


_SPECS = [
    SystemSpec("nes", "Nintendo Entertainment System", "Nintendo_-_Nintendo_Entertainment_System"),
    SystemSpec("snes", "Super Nintendo", "Nintendo_-_Super_Nintendo_Entertainment_System"),
    SystemSpec("n64", "Nintendo 64", "Nintendo_-_Nintendo_64"),
    SystemSpec("gc", "GameCube", "Nintendo_-_GameCube"),
    SystemSpec("gb", "Game Boy", "Nintendo_-_Game_Boy"),
    SystemSpec("gbc", "Game Boy Color", "Nintendo_-_Game_Boy_Color"),
    SystemSpec("gba", "Game Boy Advance", "Nintendo_-_Game_Boy_Advance"),
    SystemSpec("nds", "Nintendo DS", "Nintendo_-_Nintendo_DS"),
    SystemSpec("switch", "Nintendo Switch", "Nintendo_-_Nintendo_Switch", is_switch=True),
    SystemSpec("psx", "PlayStation", "Sony_-_PlayStation"),
    SystemSpec("ps2", "PlayStation 2", "Sony_-_PlayStation_2"),
    SystemSpec("psp", "PlayStation Portable", "Sony_-_PlayStation_Portable"),
    SystemSpec("megadrive", "Mega Drive / Genesis", "Sega_-_Mega_Drive_-_Genesis"),
    SystemSpec("saturn", "Sega Saturn", "Sega_-_Saturn"),
    SystemSpec("dreamcast", "Dreamcast", "Sega_-_Dreamcast"),
]

_ALIASES = {
    "nes": ["nes", "nintendo - nintendo entertainment system", "famicom"],
    "snes": ["snes", "nintendo - super nintendo entertainment system", "sfc"],
    "n64": ["n64", "nintendo - nintendo 64"],
    "gc": ["gc", "gamecube", "nintendo - gamecube", "ngc"],
    "gb": ["gb", "nintendo - game boy"],
    "gbc": ["gbc", "nintendo - game boy color"],
    "gba": ["gba", "nintendo - game boy advance"],
    "nds": ["nds", "nintendo - nintendo ds"],
    "switch": ["switch", "nintendo - nintendo switch", "nsw"],
    "psx": ["psx", "ps1", "sony - playstation"],
    "ps2": ["ps2", "sony - playstation 2"],
    "psp": ["psp", "sony - playstation portable"],
    "megadrive": ["megadrive", "genesis", "md", "sega - mega drive - genesis"],
    "saturn": ["saturn", "sega - saturn"],
    "dreamcast": ["dreamcast", "dc", "sega - dreamcast"],
}

_BY_ALIAS = {
    alias: spec
    for spec in _SPECS
    for alias in _ALIASES[spec.code]
}


def lookup_system(directory_name: str) -> SystemSpec | None:
    return _BY_ALIAS.get(directory_name.strip().lower())
```

- [x] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: directory-to-system mapping with aliases"`

---

### Task 7: Synchronizacja skanu z bazą (`scan.py`)

**Files:**
- Create: `backend/library/scanner/scan.py`
- Test: `backend/library/tests/test_scan.py`

**Interfaces:**
- Produces: `run_scan() -> ScanRun` — pełny przebieg: katalogi 1. poziomu `LIBRARY_ROOT` → Systemy (znane z mapy; nieznane → `System(code=slug, needs_config=True)`), grupy → Gry/Pliki, przyrostowo, usuwanie znikniętych plików i osieroconych gier, liczniki + błędy w `ScanRun`. Wykorzystywane przez task (Task 8) i M2 (hook dopasowania okładek).

- [ ] **Step 1: Failing testy**

`backend/library/tests/test_scan.py`:

```python
import pytest
from django.test import override_settings

from library.models import Game, GameFile, ScanRun, System
from library.scanner.scan import run_scan


@pytest.fixture
def library(tmp_path):
    d = tmp_path / "snes"
    d.mkdir()
    (d / "Super Mario World (USA).sfc").write_bytes(b"a" * 10)
    (d / "F-Zero (USA).sfc").write_bytes(b"b" * 20)
    return tmp_path


@pytest.mark.django_db
def test_initial_scan_creates_everything(library):
    with override_settings(LIBRARY_ROOT=library):
        run = run_scan()
    assert run.status == ScanRun.Status.SUCCESS
    assert System.objects.get(code="snes")
    assert Game.objects.count() == 2
    assert GameFile.objects.count() == 2
    assert run.files_created == 2


@pytest.mark.django_db
def test_rescan_is_idempotent(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        run2 = run_scan()
    assert (run2.files_created, run2.files_updated, run2.files_deleted) == (0, 0, 0)


@pytest.mark.django_db
def test_deleted_file_removes_game(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        (library / "snes" / "F-Zero (USA).sfc").unlink()
        run2 = run_scan()
    assert run2.files_deleted == 1
    assert not Game.objects.filter(title="F-Zero").exists()


@pytest.mark.django_db
def test_modified_file_updates_size(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        (library / "snes" / "F-Zero (USA).sfc").write_bytes(b"c" * 99)
        run2 = run_scan()
    assert run2.files_updated == 1
    assert GameFile.objects.get(relative_path__contains="F-Zero").size == 99


@pytest.mark.django_db
def test_unknown_directory_flagged(tmp_path):
    (tmp_path / "Dziwny Folder").mkdir()
    (tmp_path / "Dziwny Folder" / "x.rom").write_bytes(b"x")
    with override_settings(LIBRARY_ROOT=tmp_path):
        run_scan()
    assert System.objects.get(directory="Dziwny Folder").needs_config is True


@pytest.mark.django_db
def test_switch_family_with_and_without_title_id_is_one_game(tmp_path):
    # base z title-id (klucz = prefiks), update bez title-id (klucz = tytuł):
    # bez fallbacku po normalized_title drugi create łamie UniqueConstraint
    # i wywraca cały skan.
    d = tmp_path / "switch"
    d.mkdir()
    (d / "Celeste [01002B30028F6000][v0].nsp").write_bytes(b"a")
    (d / "Celeste (UPD) (v1.2.6).nsp").write_bytes(b"b")
    with override_settings(LIBRARY_ROOT=tmp_path):
        run = run_scan()
    assert run.status == ScanRun.Status.SUCCESS
    game = Game.objects.get(system__code="switch")
    assert game.switch_title_prefix == "01002B30028F"
    assert sorted(game.files.values_list("role", flat=True)) == ["base", "update"]


@pytest.mark.django_db
def test_missing_library_root_marks_run_failed(tmp_path):
    with override_settings(LIBRARY_ROOT=tmp_path / "nie-ma"):
        run = run_scan()
    assert run.status == ScanRun.Status.FAILED
    assert run.errors and run.finished_at is not None


@pytest.mark.django_db
def test_system_error_is_recorded_and_scan_continues(library, monkeypatch):
    import library.scanner.scan as scan_module

    def boom(*args, **kwargs):
        raise OSError("dysk odpięty")

    monkeypatch.setattr(scan_module, "group_system_dir", boom)
    with override_settings(LIBRARY_ROOT=library):
        run = run_scan()
    assert run.status == ScanRun.Status.SUCCESS
    assert any("dysk odpięty" in e for e in run.errors)
```

- [ ] **Step 2: FAIL** — `pytest library/tests/test_scan.py -v`

- [ ] **Step 3: Implementacja**

`backend/library/scanner/scan.py`:

```python
from django.conf import settings
from django.utils import timezone
from django.utils.text import slugify

from library.models import Game, GameFile, ScanRun, System

from .grouping import group_system_dir
from .systems_map import lookup_system


def _find_game(system: System, group) -> Game | None:
    """Najpierw po title-id (Switch), potem po znormalizowanym tytule.

    Fallback po tytule jest konieczny: grupa z title-id i grupa bez niego
    (np. update nazwany bez tagu) mają ten sam normalized_title, a
    UniqueConstraint (system, normalized_title) nie pozwoli na dwie gry.
    """
    if group.switch_title_prefix:
        game = Game.objects.filter(
            system=system, switch_title_prefix=group.switch_title_prefix
        ).first()
        if game is not None:
            return game
    game = Game.objects.filter(
        system=system, normalized_title=group.normalized_title
    ).first()
    if game is not None and group.switch_title_prefix and not game.switch_title_prefix:
        game.switch_title_prefix = group.switch_title_prefix
        game.save(update_fields=["switch_title_prefix"])
    return game


def _sync_group(system: System, group, run: ScanRun, seen: set[str]) -> None:
    game = _find_game(system, group)
    if game is None:
        game = Game.objects.create(
            system=system,
            title=group.title,
            normalized_title=group.normalized_title,
            switch_title_prefix=group.switch_title_prefix,
        )
        run.games_created += 1
    for entry in group.files:
        seen.add(entry.relative_path)
        existing = GameFile.objects.filter(relative_path=entry.relative_path).first()
        if existing is None:
            GameFile.objects.create(
                game=game,
                relative_path=entry.relative_path,
                role=entry.role,
                disc_number=entry.disc_number,
                version=entry.version,
                size=entry.size,
                mtime_ns=entry.mtime_ns,
            )
            run.files_created += 1
        elif (existing.size, existing.mtime_ns) != (entry.size, entry.mtime_ns):
            existing.size, existing.mtime_ns = entry.size, entry.mtime_ns
            existing.save(update_fields=["size", "mtime_ns"])
            run.files_updated += 1


def run_scan() -> ScanRun:
    run = ScanRun.objects.create()
    seen: set[str] = set()
    root = settings.LIBRARY_ROOT
    try:
        for system_dir in sorted(p for p in root.iterdir() if p.is_dir()):
            spec = lookup_system(system_dir.name)
            if spec:
                system, _ = System.objects.update_or_create(
                    directory=system_dir.name,
                    defaults={
                        "code": spec.code,
                        "name": spec.name,
                        "thumbnail_repo": spec.thumbnail_repo,
                    },
                )
                is_switch = spec.is_switch
            else:
                system, _ = System.objects.get_or_create(
                    directory=system_dir.name,
                    defaults={
                        "code": slugify(system_dir.name),
                        "name": system_dir.name,
                        "needs_config": True,
                    },
                )
                is_switch = False
            try:
                for group in group_system_dir(system_dir, root, is_switch=is_switch):
                    _sync_group(system, group, run, seen)
            except OSError as exc:
                run.errors.append(f"{system_dir.name}: {exc}")
        # różnica liczona po stronie Pythona — `exclude(relative_path__in=seen)`
        # przy dużej bibliotece przekracza limit parametrów zapytania SQLite
        stale_ids = [
            pk
            for pk, path in GameFile.objects.values_list("pk", "relative_path")
            if path not in seen
        ]
        run.files_deleted = len(stale_ids)
        for i in range(0, len(stale_ids), 500):
            GameFile.objects.filter(pk__in=stale_ids[i : i + 500]).delete()
        Game.objects.filter(files__isnull=True).delete()
        run.status = ScanRun.Status.SUCCESS
    except Exception as exc:  # awaria całego skanu
        run.status = ScanRun.Status.FAILED
        run.errors.append(str(exc))
    run.finished_at = timezone.now()
    run.save()
    return run
```

- [ ] **Step 4: PASS** — `pytest library/tests/test_scan.py -v` (i cały `pytest`, bo grouping/naming już są)

- [ ] **Step 5: Commit** — `git commit -m "feat: incremental library scan synchronizing DB with disk"`

---

### Task 8: Task w tle, komenda `scan`, endpoint `POST /api/scan/`

**Files:**
- Create: `backend/library/tasks.py`, `backend/library/management/__init__.py`, `backend/library/management/commands/__init__.py`, `backend/library/management/commands/scan.py`, `backend/library/api.py`, `backend/library/urls.py`
- Modify: `backend/droplet/urls.py` (include `library.urls` pod `api/`)
- Test: `backend/library/tests/test_scan_triggers.py`

**Interfaces:**
- Produces:
  - `library.tasks.scan_library` — task (`@task()`) wołający `run_scan()`.
  - `python manage.py scan` — bieg synchroniczny (dla crona), wypisuje statystyki.
  - `POST /api/scan/` (auth) → `202 {"enqueued": true}`.

- [ ] **Step 1: Failing testy**

`backend/library/tests/test_scan_triggers.py`:

```python
import pytest
from django.core.management import call_command
from django.test import override_settings
from rest_framework.test import APIClient

from library.models import ScanRun

# fixture `auth_client` pochodzi z backend/conftest.py (M0 Task 7a)


@pytest.mark.django_db
def test_scan_command_runs(tmp_path, capsys):
    with override_settings(LIBRARY_ROOT=tmp_path):
        call_command("scan")
    assert ScanRun.objects.count() == 1


@pytest.mark.django_db
def test_scan_endpoint_enqueues(auth_client, tmp_path):
    with override_settings(LIBRARY_ROOT=tmp_path):
        resp = auth_client.post("/api/scan/")
    assert resp.status_code == 202
    assert ScanRun.objects.count() == 1  # ImmediateBackend wykonuje od razu


@pytest.mark.django_db
def test_scan_endpoint_requires_auth():
    assert APIClient().post("/api/scan/").status_code == 401
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja**

`backend/library/tasks.py`:

```python
from django.tasks import task

from .scanner.scan import run_scan


@task()
def scan_library() -> int:
    run = run_scan()
    return run.pk
```

`backend/library/management/commands/scan.py`:

```python
from django.core.management.base import BaseCommand

from library.scanner.scan import run_scan


class Command(BaseCommand):
    help = "Scan the ROM library synchronously."

    def handle(self, *args, **options):
        run = run_scan()
        self.stdout.write(
            f"{run.status}: +{run.files_created} ~{run.files_updated} "
            f"-{run.files_deleted} files, errors: {len(run.errors)}"
        )
```

`backend/library/api.py`:

```python
from rest_framework.decorators import api_view
from rest_framework.response import Response

from .tasks import scan_library


@api_view(["POST"])
def trigger_scan(request):
    scan_library.enqueue()
    return Response({"enqueued": True}, status=202)
```

`backend/library/urls.py`:

```python
from django.urls import path

from . import api

urlpatterns = [
    path("scan/", api.trigger_scan, name="trigger-scan"),
]
```

W `droplet/urls.py` dodaj `path("api/", include("library.urls")),`.

- [ ] **Step 4: PASS** — `pytest library/tests/test_scan_triggers.py -v`

- [ ] **Step 5: Commit** — `git commit -m "feat: scan task, management command and API trigger"`

---

### Task 9: Admin do przeglądania i korekt

**Files:**
- Modify: `backend/library/admin.py`
- Test: `backend/library/tests/test_admin.py`

**Interfaces:**
- Produces: admin z filtrami/szukajkami; `GameFile.game` edytowalne (przepięcie pliku do innej gry) i `role`/`disc_number`/`version` edytowalne; akcja "Uruchom skan" na liście ScanRun; System z edycją `thumbnail_repo`/`needs_config`.

- [ ] **Step 1: Failing test (smoke)**

`backend/library/tests/test_admin.py`:

```python
import pytest
from django.contrib.auth.models import User


@pytest.fixture
def admin_client_(client, db):
    User.objects.create_superuser(username="root", password="root123")
    client.login(username="root", password="root123")
    return client


@pytest.mark.django_db
@pytest.mark.parametrize(
    "url",
    [
        "/admin/library/system/",
        "/admin/library/game/",
        "/admin/library/gamefile/",
        "/admin/library/scanrun/",
    ],
)
def test_admin_pages_render(admin_client_, url):
    assert admin_client_.get(url).status_code == 200


@pytest.mark.django_db
def test_game_list_shows_file_count(admin_client_):
    from library.models import Game, GameFile, System

    s = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    GameFile.objects.create(game=g, relative_path="snes/m.sfc", size=1, mtime_ns=1)
    resp = admin_client_.get("/admin/library/game/")
    assert resp.status_code == 200
    assert b"Mario" in resp.content  # kolumna file_count renderuje się bez błędu


@pytest.mark.django_db
def test_run_scan_action_enqueues(admin_client_, tmp_path):
    from django.test import override_settings

    from library.models import ScanRun

    old = ScanRun.objects.create()
    with override_settings(LIBRARY_ROOT=tmp_path):
        resp = admin_client_.post(
            "/admin/library/scanrun/",
            {"action": "run_scan_action", "_selected_action": [old.pk]},
            follow=True,
        )
    assert resp.status_code == 200
    assert ScanRun.objects.count() == 2  # ImmediateBackend wykonał skan od razu
```

- [ ] **Step 2: FAIL** — `pytest library/tests/test_admin.py -v --no-cov` (testy akcji i kolumny nie przechodzą na prostych rejestracjach).

- [ ] **Step 3: Implementacja**

`backend/library/admin.py` (zastąp):

```python
from django.contrib import admin

from .models import Game, GameFile, ScanRun, System
from .tasks import scan_library


@admin.register(System)
class SystemAdmin(admin.ModelAdmin):
    list_display = ["code", "name", "directory", "thumbnail_repo", "needs_config"]
    list_editable = ["thumbnail_repo", "needs_config"]
    list_filter = ["needs_config"]


class GameFileInline(admin.TabularInline):
    model = GameFile
    fields = ["relative_path", "role", "disc_number", "version", "size"]
    readonly_fields = ["relative_path", "size"]
    extra = 0


@admin.register(Game)
class GameAdmin(admin.ModelAdmin):
    list_display = ["title", "system", "file_count"]
    list_filter = ["system"]
    search_fields = ["title", "normalized_title"]
    inlines = [GameFileInline]

    @admin.display(description="pliki")
    def file_count(self, obj):
        return obj.files.count()


@admin.register(GameFile)
class GameFileAdmin(admin.ModelAdmin):
    list_display = ["relative_path", "game", "role", "disc_number", "version", "size"]
    list_filter = ["role", "game__system"]
    search_fields = ["relative_path", "game__title"]
    autocomplete_fields = ["game"]
    list_editable = ["role"]


@admin.register(ScanRun)
class ScanRunAdmin(admin.ModelAdmin):
    list_display = [
        "started_at", "finished_at", "status",
        "games_created", "files_created", "files_updated", "files_deleted",
    ]
    actions = ["run_scan_action"]

    @admin.action(description="Uruchom skan biblioteki")
    def run_scan_action(self, request, queryset):
        scan_library.enqueue()
        self.message_user(request, "Skan dodany do kolejki")
```

Uwaga: `autocomplete_fields` wymaga `search_fields` w `GameAdmin` — jest.

- [ ] **Step 4: PASS** — `pytest library/tests/test_admin.py -v`

- [ ] **Step 5: Commit** — `git commit -m "feat: admin for library browsing and corrections"`

---

### Task 10: E2E skanu na fixture'owej bibliotece

**Files:**
- Create: `backend/e2e/test_scan_e2e.py`, pliki w `backend/e2e/fixture-library/`

**Interfaces:**
- Consumes: harness e2e z M0 (fixture-library montowana jako `/library:ro` w biegu e2e).
- Produces: fixture'owa biblioteka w repo (małe pliki-atrapy, commitowane) pokrywająca wszystkie ścieżki grupowania; test e2e pełnej pętli: trigger skanu przez API → poprawny indeks.

- [ ] **Step 1: Zbuduj fixture-library**

```bash
cd backend/e2e/fixture-library
mkdir -p snes psx switch "Dziwny Folder"
printf 'AAAA' > "snes/Super Mario World (USA).sfc"
printf 'FILE "Tekken (USA).bin" BINARY\n' > "psx/Tekken (USA).cue"
printf 'BINBIN' > "psx/Tekken (USA).bin"
printf 'HK' > "switch/Hollow Knight [0100633007D48000][v0].nsp"
printf 'HKU' > "switch/Hollow Knight [UPD][0100633007D48800][v196608].nsp"
printf 'X' > "Dziwny Folder/tajemniczy.rom"
rm .gitkeep
```

- [ ] **Step 2: Napisz failing test e2e**

`backend/e2e/test_scan_e2e.py`:

```python
import time

import requests


def test_scan_via_api_indexes_fixture_library(base_url, auth):
    resp = requests.post(f"{base_url}/api/scan/", headers=auth, timeout=10)
    assert resp.status_code == 202
    # worker przetwarza task w tle — poczekaj aż skan się zakończy,
    # potem drugi bieg synchroniczny nie powinien nic zmienić (idempotencja):
    time.sleep(5)
    resp2 = requests.post(f"{base_url}/api/scan/", headers=auth, timeout=10)
    assert resp2.status_code == 202


def test_scan_requires_auth(base_url):
    assert requests.post(f"{base_url}/api/scan/", timeout=10).status_code == 401
```

Uwaga wykonawcza: pełna asercja zawartości indeksu (3 gry: Mario, Tekken jako
cue+bin, Hollow Knight base+update; „Dziwny Folder" z `needs_config`) dochodzi
w M3, gdy istnieje `GET /api/games/` — wtedy rozszerz ten plik o asercje na
liczbę i role (M3 Task 5 ma to w zakresie). W M1 weryfikację zawartości zrób
przez `docker compose exec web python manage.py shell -c "from library.models import Game; print(Game.objects.count())"`
w Step 3.

- [ ] **Step 3: Uruchom e2e + weryfikacja zawartości**

Run: `./scripts/e2e_backend.sh` — PASS; w osobnym biegu compose e2e sprawdź `Game.objects.count() == 4` (3 znane + 1 z Dziwnego Folderu) jak w uwadze wyżej.

- [ ] **Step 4: Commit** — `git add backend/e2e && git commit -m "test: e2e scan flow on fixture library"`

---

### Task 11: Skan prawdziwej biblioteki (weryfikacja kryteriów M1)

**Files:**
- Modify: `docs/deploy.md` (sekcja cron — jeśli nie powstała w M0, dopisz teraz)

- [ ] **Step 1: Pełne testy** — `pytest -v` (całość zielona, pokrycie 100%) oraz `./scripts/e2e_backend.sh` (PASS).

- [ ] **Step 2: Deploy na TrueNAS i skan realnych danych**

```bash
docker compose build && docker compose up -d
docker compose exec web python manage.py scan
```

Porównaj liczby gier per system w adminie z zawartością katalogów „na oko". Zanotuj rozjazdy (złe grupowanie Switcha, nieznane katalogi) — popraw w adminie lub dopisz aliasy do `systems_map.py`.

- [ ] **Step 3: Idempotencja na realnych danych** — drugi `manage.py scan` → `+0 ~0 -0`.

- [ ] **Step 4: Cron na TrueNAS** — skonfiguruj nocny `docker exec ... python manage.py scan` wg `docs/deploy.md`.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "chore: M1 wrap-up (aliases, docs)" || true`
