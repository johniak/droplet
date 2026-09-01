# M3 — API dla klienta: plan implementacji

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kompletne API pod aplikację Flutter: systemy, lista gier (paginacja/filtry/szukajka), manifest gry, pobieranie plików z HTTP Range — wszystko za tokenem, testowalne curlem.

**Architecture:** DRF w appce `library` (`serializers.py` + rozbudowa `api.py`); streaming pobierania własnym widokiem z obsługą `Range` (bez nginx — jeden użytkownik); ścieżki wyłącznie z indeksu DB + weryfikacja, że resolved path leży pod `LIBRARY_ROOT`.

**Tech Stack:** jak M0–M2, dodatkowo `django-filter>=24.0`.

**Spec:** `docs/superpowers/specs/2026-09-01-droplet-design.md` (§3.5)

## Global Constraints

- Obowiązują Global Constraints z M0–M2 — w tym **pokrycie 100%** przy każdym zadaniu i **suita e2e** (`scripts/e2e_backend.sh`).
- Kontrakt JSON (kanoniczny — M4 buduje na nim modele):

```
GET /api/systems/            -> [{"id", "code", "name", "game_count", "sort_order"}]
GET /api/games/              -> {"count", "next", "previous", "results":
                                 [{"id", "title", "system_code", "has_cover", "total_size"}]}
    query: system=<code>, search=<fraza>, ordering=title|-title|-id, page=<n>
GET /api/games/{id}/         -> {"id", "title", "system_code", "system_name", "has_cover",
                                 "files": [{"id", "name", "relative_path", "role",
                                            "disc_number", "version", "size"}]}
GET /api/files/{id}/download -> 200 pełny plik / 206 przy Range / 416 zły zakres;
                                nagłówki: Accept-Ranges, Content-Length, Content-Range (206),
                                Content-Disposition: attachment; filename="<basename>"
```

- Paginacja: `PAGE_SIZE=60` (ustawione w M0).
- Download streamuje w kawałkach 1 MiB — nigdy nie czyta całego pliku do pamięci.
- Biegi częściowe (`pytest <plik>`) z `--no-cov`; bramka = pełny `pytest`. Testy API używają fixture `auth_client` z `backend/conftest.py` (M0 Task 7a).

---

### Task 1: `GET /api/systems/`

**Files:**
- Create: `backend/library/serializers.py`
- Modify: `backend/library/api.py`, `backend/library/urls.py`
- Test: `backend/library/tests/test_api_systems.py`

**Interfaces:**
- Consumes: modele z M1.
- Produces: `SystemSerializer` (pola: `id, code, name, game_count, sort_order`); endpoint zwraca systemy posortowane po `sort_order, name`, tylko te z co najmniej 1 grą; bez paginacji (lista jest krótka).

- [x] **Step 1: Failing testy**

`backend/library/tests/test_api_systems.py`:

```python
import pytest
from rest_framework.test import APIClient

from library.models import Game, System


# fixture `auth_client` pochodzi z backend/conftest.py (M0 Task 7a)


@pytest.fixture
def data(db):
    snes = System.objects.create(code="snes", name="SNES", directory="snes", sort_order=2)
    psx = System.objects.create(code="psx", name="PlayStation", directory="psx", sort_order=1)
    System.objects.create(code="pusty", name="Pusty", directory="pusty")
    Game.objects.create(system=snes, title="Mario", normalized_title="mario")
    Game.objects.create(system=snes, title="Zelda", normalized_title="zelda")
    Game.objects.create(system=psx, title="Tekken", normalized_title="tekken")


def test_systems_sorted_with_counts(auth_client, data):
    resp = auth_client.get("/api/systems/")
    assert resp.status_code == 200
    body = resp.json()
    assert [s["code"] for s in body] == ["psx", "snes"]  # pusty odfiltrowany
    assert body[1]["game_count"] == 2


def test_systems_require_auth(db):
    assert APIClient().get("/api/systems/").status_code == 401
```

- [x] **Step 2: FAIL**

- [x] **Step 3: Implementacja**

`backend/library/serializers.py`:

```python
from rest_framework import serializers

from .models import Game, GameFile, System


class SystemSerializer(serializers.ModelSerializer):
    game_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = System
        fields = ["id", "code", "name", "game_count", "sort_order"]
```

W `backend/library/api.py`:

```python
from django.db.models import Count
from rest_framework.generics import ListAPIView

from .models import System
from .serializers import SystemSerializer


class SystemListView(ListAPIView):
    serializer_class = SystemSerializer
    pagination_class = None

    def get_queryset(self):
        return (
            System.objects.annotate(game_count=Count("games"))
            .filter(game_count__gt=0)
            .order_by("sort_order", "name")
        )
```

`urls.py`: `path("systems/", api.SystemListView.as_view(), name="systems"),`

- [x] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: systems endpoint with game counts"`

---

### Task 2: `GET /api/games/` (lista)

**Files:**
- Modify: `backend/requirements.txt` (`django-filter>=24.0`), `backend/droplet/settings.py`, `backend/library/serializers.py`, `backend/library/api.py`, `backend/library/urls.py`
- Test: `backend/library/tests/test_api_games.py`

**Interfaces:**
- Produces: `GameListSerializer` (`id, title, system_code, has_cover, total_size`); filtr `?system=<code>`, `?search=` po `title`/`normalized_title`, `?ordering=` (`title`, `-title`, `-id`; default `title`); paginacja PageNumber.

- [x] **Step 1: Failing testy**

`backend/library/tests/test_api_games.py`:

```python
import pytest
from rest_framework.test import APIClient

from covers.models import Cover
from library.models import Game, GameFile, System


# fixture `auth_client` pochodzi z backend/conftest.py (M0 Task 7a)


@pytest.fixture
def data(db):
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    psx = System.objects.create(code="psx", name="PSX", directory="psx")
    mario = Game.objects.create(system=snes, title="Super Mario World", normalized_title="super mario world")
    zelda = Game.objects.create(system=snes, title="Zelda", normalized_title="zelda")
    tekken = Game.objects.create(system=psx, title="Tekken", normalized_title="tekken")
    GameFile.objects.create(game=mario, relative_path="snes/m.sfc", size=100, mtime_ns=1)
    GameFile.objects.create(game=tekken, relative_path="psx/t.cue", size=10, mtime_ns=1)
    GameFile.objects.create(game=tekken, relative_path="psx/t.bin", size=990, mtime_ns=1, role="support")
    Cover.objects.create(game=mario, source=Cover.Source.LIBRETRO, match_name="m")
    return {"mario": mario, "tekken": tekken}


def test_list_shape_and_order(auth_client, data):
    body = auth_client.get("/api/games/").json()
    assert body["count"] == 3
    titles = [g["title"] for g in body["results"]]
    assert titles == ["Super Mario World", "Tekken", "Zelda"]
    mario = body["results"][0]
    assert mario["system_code"] == "snes"
    assert mario["has_cover"] is True
    assert mario["total_size"] == 100


def test_filter_by_system(auth_client, data):
    body = auth_client.get("/api/games/?system=psx").json()
    assert [g["title"] for g in body["results"]] == ["Tekken"]
    assert body["results"][0]["total_size"] == 1000


def test_search(auth_client, data):
    body = auth_client.get("/api/games/?search=mario").json()
    assert body["count"] == 1


def test_games_require_auth(db):
    assert APIClient().get("/api/games/").status_code == 401
```

- [x] **Step 2: FAIL**

- [x] **Step 3: Implementacja**

`pip install django-filter`, do `INSTALLED_APPS` dopisz `"django_filters"`. W `serializers.py`:

```python
class GameListSerializer(serializers.ModelSerializer):
    system_code = serializers.CharField(source="system.code", read_only=True)
    has_cover = serializers.BooleanField(read_only=True)
    total_size = serializers.IntegerField(read_only=True)

    class Meta:
        model = Game
        fields = ["id", "title", "system_code", "has_cover", "total_size"]
```

W `api.py` (wersja docelowa — filtr działa jako `?system=<code>`, nie `?system__code=`, stąd własny `FilterSet`):

```python
import django_filters
from django.db.models import BigIntegerField, Exists, OuterRef, Sum, Value
from django.db.models.functions import Coalesce
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework.filters import OrderingFilter, SearchFilter

from covers.models import Cover
from .models import Game
from .serializers import GameListSerializer


def annotated_games():
    return Game.objects.select_related("system").annotate(
        has_cover=Exists(Cover.objects.filter(game=OuterRef("pk"))),
        # jawny output_field: bez niego Django potrafi rzucić
        # "Expression contains mixed types" (BigIntegerField vs IntegerField)
        total_size=Coalesce(
            Sum("files__size"), Value(0), output_field=BigIntegerField()
        ),
    )


class GameFilter(django_filters.FilterSet):
    system = django_filters.CharFilter(field_name="system__code")

    class Meta:
        model = Game
        fields = ["system"]


class GameListView(ListAPIView):
    serializer_class = GameListSerializer
    filter_backends = [DjangoFilterBackend, SearchFilter, OrderingFilter]
    filterset_class = GameFilter
    search_fields = ["title", "normalized_title"]
    ordering_fields = ["title", "id"]
    ordering = ["title"]

    def get_queryset(self):
        return annotated_games()
```

`urls.py`: `path("games/", api.GameListView.as_view(), name="games"),`

- [x] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: games list with filtering, search and pagination"`

---

### Task 3: `GET /api/games/{id}/` (manifest)

**Files:**
- Modify: `backend/library/serializers.py`, `backend/library/api.py`, `backend/library/urls.py`
- Test: `backend/library/tests/test_api_game_detail.py`

**Interfaces:**
- Produces: `GameDetailSerializer` — pola gry jak lista + `system_name` + `files` (`GameFileSerializer`: `id, name (basename), relative_path, role, disc_number, version, size`), pliki posortowane: `base, update, dlc, disc (po disc_number), support, other`.

- [x] **Step 1: Failing testy**

`backend/library/tests/test_api_game_detail.py`:

```python
import pytest
from rest_framework.test import APIClient

from library.models import Game, GameFile, System


# fixture `auth_client` pochodzi z backend/conftest.py (M0 Task 7a)


@pytest.fixture
def switch_game(db):
    sw = System.objects.create(code="switch", name="Switch", directory="switch")
    g = Game.objects.create(system=sw, title="Hollow Knight", normalized_title="hollow knight")
    GameFile.objects.create(game=g, relative_path="switch/hk-dlc.nsp", role="dlc", size=3, mtime_ns=1)
    GameFile.objects.create(game=g, relative_path="switch/hk.nsp", role="base", size=1, mtime_ns=1)
    GameFile.objects.create(game=g, relative_path="switch/hk-upd.nsp", role="update", version="v196608", size=2, mtime_ns=1)
    return g


def test_detail_manifest_sorted(auth_client, switch_game):
    body = auth_client.get(f"/api/games/{switch_game.id}/").json()
    assert body["system_name"] == "Switch"
    assert [f["role"] for f in body["files"]] == ["base", "update", "dlc"]
    assert body["files"][0]["name"] == "hk.nsp"
    assert body["files"][1]["version"] == "v196608"


def test_detail_404(auth_client):
    assert auth_client.get("/api/games/99999/").status_code == 404
```

- [x] **Step 2: FAIL**

- [x] **Step 3: Implementacja**

W `serializers.py`:

```python
import posixpath

ROLE_ORDER = {"base": 0, "update": 1, "dlc": 2, "disc": 3, "support": 4, "other": 5}


class GameFileSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()

    class Meta:
        model = GameFile
        fields = ["id", "name", "relative_path", "role", "disc_number", "version", "size"]

    def get_name(self, obj):
        return posixpath.basename(obj.relative_path)


class GameDetailSerializer(GameListSerializer):
    system_name = serializers.CharField(source="system.name", read_only=True)
    files = serializers.SerializerMethodField()

    class Meta(GameListSerializer.Meta):
        fields = GameListSerializer.Meta.fields + ["system_name", "files"]

    def get_files(self, obj):
        files = sorted(
            obj.files.all(),
            key=lambda f: (ROLE_ORDER.get(f.role, 9), f.disc_number or 0, f.relative_path),
        )
        return GameFileSerializer(files, many=True).data
```

W `api.py`:

```python
from rest_framework.generics import RetrieveAPIView

from .serializers import GameDetailSerializer


class GameDetailView(RetrieveAPIView):
    serializer_class = GameDetailSerializer

    def get_queryset(self):
        return annotated_games().prefetch_related("files")
```

`urls.py`: `path("games/<int:pk>/", api.GameDetailView.as_view(), name="game-detail"),`

- [x] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: game detail endpoint with sorted file manifest"`

---

### Task 4: Pobieranie z HTTP Range

**Files:**
- Create: `backend/library/download.py`
- Modify: `backend/library/urls.py`
- Test: `backend/library/tests/test_download.py`

**Interfaces:**
- Produces: `GET /api/files/{id}/download`:
  - bez `Range` → `200`, cały plik, `Content-Length`, `Accept-Ranges: bytes`, `Content-Disposition: attachment; filename="..."`,
  - `Range: bytes=S-` / `bytes=S-E` → `206` + `Content-Range: bytes S-E/total`,
  - `Range` niesparsowalny lub `S >= size` → `416` + `Content-Range: bytes */total`,
  - plik z indeksu, ale resolved path poza `LIBRARY_ROOT` (symlink) → `404`,
  - streaming w kawałkach 1 MiB.

- [x] **Step 1: Failing testy**

`backend/library/tests/test_download.py`:

```python
import pytest
from django.contrib.auth.models import User
from django.test import override_settings
from rest_framework.test import APIClient

from library.models import Game, GameFile, System

CONTENT = bytes(range(256)) * 4  # 1024 bajty


# fixture `auth_client` pochodzi z backend/conftest.py (M0 Task 7a)


@pytest.fixture
def gamefile(db, tmp_path):
    (tmp_path / "snes").mkdir()
    (tmp_path / "snes" / "Mario (USA).sfc").write_bytes(CONTENT)
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    gf = GameFile.objects.create(
        game=g, relative_path="snes/Mario (USA).sfc", size=1024, mtime_ns=1
    )
    return gf, tmp_path


def _get(client, gf, root, **headers):
    with override_settings(LIBRARY_ROOT=root):
        return client.get(f"/api/files/{gf.id}/download", **headers)


def test_full_download(auth_client, gamefile):
    gf, root = gamefile
    resp = _get(auth_client, gf, root)
    assert resp.status_code == 200
    assert resp["Accept-Ranges"] == "bytes"
    assert resp["Content-Length"] == "1024"
    assert 'filename="Mario (USA).sfc"' in resp["Content-Disposition"]
    assert b"".join(resp.streaming_content) == CONTENT


def test_range_resume(auth_client, gamefile):
    gf, root = gamefile
    resp = _get(auth_client, gf, root, HTTP_RANGE="bytes=1000-")
    assert resp.status_code == 206
    assert resp["Content-Range"] == "bytes 1000-1023/1024"
    assert b"".join(resp.streaming_content) == CONTENT[1000:]


def test_range_window(auth_client, gamefile):
    gf, root = gamefile
    resp = _get(auth_client, gf, root, HTTP_RANGE="bytes=0-99")
    assert resp.status_code == 206
    assert len(b"".join(resp.streaming_content)) == 100


def test_bad_range_416(auth_client, gamefile):
    gf, root = gamefile
    assert _get(auth_client, gf, root, HTTP_RANGE="bytes=99999-").status_code == 416
    assert _get(auth_client, gf, root, HTTP_RANGE="chunks=1-2").status_code == 416


def test_download_requires_auth(gamefile):
    gf, root = gamefile
    with override_settings(LIBRARY_ROOT=root):
        assert APIClient().get(f"/api/files/{gf.id}/download").status_code == 401


def test_symlink_escape_is_404(auth_client, gamefile, tmp_path):
    gf, root = gamefile
    outside = tmp_path.parent / "poza.bin"
    outside.write_bytes(b"tajne")
    (root / "snes" / "Zly.sfc").symlink_to(outside)
    gf2 = GameFile.objects.create(
        game=gf.game, relative_path="snes/Zly.sfc", size=5, mtime_ns=1
    )
    assert _get(auth_client, gf2, root).status_code == 404


def test_stream_stops_when_file_shrinks_mid_transfer(auth_client, gamefile):
    # StreamingHttpResponse jest leniwa — plik czytany dopiero przy iteracji;
    # pokrywa gałąź `if not chunk` w _iter_file (bez niej pętla by się zawiesiła)
    gf, root = gamefile
    resp = _get(auth_client, gf, root)
    (root / "snes" / "Mario (USA).sfc").write_bytes(CONTENT[:10])
    assert b"".join(resp.streaming_content) == CONTENT[:10]
```

- [x] **Step 2: FAIL**

- [x] **Step 3: Implementacja**

`backend/library/download.py`:

```python
import posixpath
import re

from django.conf import settings
from django.http import Http404, HttpResponse, StreamingHttpResponse
from rest_framework.decorators import api_view
from rest_framework.generics import get_object_or_404

from .models import GameFile

CHUNK = 1024 * 1024
_RANGE = re.compile(r"^bytes=(\d+)-(\d*)$")


def _iter_file(path, start: int, length: int):
    with open(path, "rb") as f:
        f.seek(start)
        remaining = length
        while remaining > 0:
            chunk = f.read(min(CHUNK, remaining))
            if not chunk:
                return
            remaining -= len(chunk)
            yield chunk


@api_view(["GET"])
def file_download(request, pk: int):
    gf = get_object_or_404(GameFile, pk=pk)
    path = (settings.LIBRARY_ROOT / gf.relative_path).resolve()
    library_root = settings.LIBRARY_ROOT.resolve()
    if not path.is_relative_to(library_root) or not path.is_file():
        raise Http404
    size = path.stat().st_size
    filename = posixpath.basename(gf.relative_path)
    range_header = request.headers.get("Range")

    if range_header:
        m = _RANGE.match(range_header.strip())
        if not m or int(m.group(1)) >= size:
            resp = HttpResponse(status=416)
            resp["Content-Range"] = f"bytes */{size}"
            return resp
        start = int(m.group(1))
        end = int(m.group(2)) if m.group(2) else size - 1
        end = min(end, size - 1)
        resp = StreamingHttpResponse(
            _iter_file(path, start, end - start + 1),
            status=206,
            content_type="application/octet-stream",
        )
        resp["Content-Range"] = f"bytes {start}-{end}/{size}"
        resp["Content-Length"] = str(end - start + 1)
    else:
        resp = StreamingHttpResponse(
            _iter_file(path, 0, size), content_type="application/octet-stream"
        )
        resp["Content-Length"] = str(size)

    resp["Accept-Ranges"] = "bytes"
    resp["Content-Disposition"] = f'attachment; filename="{filename}"'
    return resp
```

`urls.py`: `path("files/<int:pk>/download", download.file_download, name="file-download"),` (+ import `from . import download`).

- [x] **Step 4: PASS** — `pytest library/tests/test_download.py -v`

- [x] **Step 5: Commit** — `git commit -m "feat: file download with HTTP range resume and path safety"`

---

### Task 5: E2E pełnego flow API (fixture-library)

**Files:**
- Create: `backend/e2e/test_api_e2e.py`
- Modify: `backend/e2e/test_scan_e2e.py` (dopisz asercje zawartości — patrz uwaga w planie M1 Task 10)

**Interfaces:**
- Consumes: harness M0, fixture-library M1 (Mario/snes, Tekken cue+bin/psx, Hollow Knight base+update/switch, Dziwny Folder).

- [x] **Step 1: Napisz testy e2e**

`backend/e2e/test_api_e2e.py`:

```python
import time

import requests


def _scan_and_wait(base_url, auth):
    requests.post(f"{base_url}/api/scan/", headers=auth, timeout=10)
    for _ in range(30):
        games = requests.get(f"{base_url}/api/games/", headers=auth, timeout=10).json()
        if games["count"] >= 4:
            return games
        time.sleep(1)
    raise AssertionError("scan nie zaindeksował fixture-library")


def test_full_flow(base_url, auth):
    games = _scan_and_wait(base_url, auth)
    assert games["count"] == 4

    systems = requests.get(f"{base_url}/api/systems/", headers=auth, timeout=10).json()
    assert {s["code"] for s in systems} >= {"snes", "psx", "switch"}

    hollow = requests.get(
        f"{base_url}/api/games/", headers=auth, timeout=10,
        params={"search": "hollow"},
    ).json()["results"][0]
    detail = requests.get(
        f"{base_url}/api/games/{hollow['id']}/", headers=auth, timeout=10
    ).json()
    assert [f["role"] for f in detail["files"]] == ["base", "update"]

    tekken = requests.get(
        f"{base_url}/api/games/", headers=auth, timeout=10,
        params={"search": "tekken"},
    ).json()["results"][0]
    tekken_detail = requests.get(
        f"{base_url}/api/games/{tekken['id']}/", headers=auth, timeout=10
    ).json()
    assert {f["role"] for f in tekken_detail["files"]} == {"base", "support"}


def test_download_with_range_resume(base_url, auth):
    games = _scan_and_wait(base_url, auth)
    mario = next(g for g in games["results"] if "Mario" in g["title"])
    file_id = requests.get(
        f"{base_url}/api/games/{mario['id']}/", headers=auth, timeout=10
    ).json()["files"][0]["id"]
    url = f"{base_url}/api/files/{file_id}/download"

    full = requests.get(url, headers=auth, timeout=10)
    assert full.status_code == 200
    assert full.headers["Accept-Ranges"] == "bytes"

    part1 = requests.get(url, headers={**auth, "Range": "bytes=0-1"}, timeout=10)
    part2 = requests.get(url, headers={**auth, "Range": "bytes=2-"}, timeout=10)
    assert part1.status_code == 206 and part2.status_code == 206
    assert part1.content + part2.content == full.content

    bad = requests.get(url, headers={**auth, "Range": "bytes=999999-"}, timeout=10)
    assert bad.status_code == 416


def test_download_requires_auth(base_url, auth):
    games = _scan_and_wait(base_url, auth)
    mario = next(g for g in games["results"] if "Mario" in g["title"])
    file_id = requests.get(
        f"{base_url}/api/games/{mario['id']}/", headers=auth, timeout=10
    ).json()["files"][0]["id"]
    resp = requests.get(f"{base_url}/api/files/{file_id}/download", timeout=10)
    assert resp.status_code == 401
```

W `test_scan_e2e.py` dopisz (zgodnie z uwagą z M1):

```python
def test_scan_result_contents(base_url, auth):
    requests.post(f"{base_url}/api/scan/", headers=auth, timeout=10)
    time.sleep(5)
    games = requests.get(f"{base_url}/api/games/", headers=auth, timeout=10).json()
    titles = {g["title"] for g in games["results"]}
    assert {"Super Mario World", "Tekken", "Hollow Knight"} <= titles
```

- [x] **Step 2: Uruchom** — `./scripts/e2e_backend.sh` → wszystkie e2e PASS.

- [x] **Step 3: Commit** — `git add backend/e2e && git commit -m "test: full API e2e flow with range resume"`

---

### Task 6: Skrypt smoke na realnym NAS + kryteria M3

**Files:**
- Create: `scripts/smoke.sh`

**Interfaces:**
- Produces: skrypt weryfikujący pełną pętlę na żywym serwerze z prawdziwymi danymi (uzupełnienie e2e, które chodzi na fixture-library).

- [ ] **Step 1: Napisz `scripts/smoke.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
BASE=${1:?usage: smoke.sh http://host:8000 user pass}
USER=${2:?} PASS=${3:?}

TOKEN=$(curl -sf -X POST "$BASE/api/auth/token/" -d "username=$USER&password=$PASS" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
AUTH="Authorization: Token $TOKEN"

echo "== systems =="; curl -sf -H "$AUTH" "$BASE/api/systems/" | python3 -m json.tool | head -20
echo "== games p1 =="; curl -sf -H "$AUTH" "$BASE/api/games/" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["count"],"gier")'

GAME_ID=$(curl -sf -H "$AUTH" "$BASE/api/games/" | python3 -c 'import sys,json;print(json.load(sys.stdin)["results"][0]["id"])')
FILE_ID=$(curl -sf -H "$AUTH" "$BASE/api/games/$GAME_ID/" | python3 -c 'import sys,json;print(json.load(sys.stdin)["files"][0]["id"])')

echo "== download z przerwaniem i wznowieniem =="
curl -sf -H "$AUTH" -r 0-99999 "$BASE/api/files/$FILE_ID/download" -o /tmp/part1
curl -sf -H "$AUTH" -C 100000 "$BASE/api/files/$FILE_ID/download" -o /tmp/part2
cat /tmp/part1 /tmp/part2 > /tmp/full-resumed
curl -sf -H "$AUTH" "$BASE/api/files/$FILE_ID/download" -o /tmp/full-direct
cmp /tmp/full-resumed /tmp/full-direct && echo "RESUME OK"

echo "== auth wymagany =="
test "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/games/")" = "401" && echo "401 OK"
echo "SMOKE PASSED"
```

`chmod +x scripts/smoke.sh`.

- [ ] **Step 2: Pełne testy + smoke na deployu**

Run: `cd backend && pytest -v` (całość zielona, pokrycie 100%), `./scripts/e2e_backend.sh` (PASS), potem `./scripts/smoke.sh http://<ip-nas>:8000 <user> <haslo>` na realnym NAS-ie.
Expected: `RESUME OK`, `401 OK`, `SMOKE PASSED`.

- [ ] **Step 3: Commit** — `git add scripts && git commit -m "feat: e2e smoke script for the API"`
