# M0 — Fundament backendu: plan implementacji

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Działający projekt Django 6 w Dockerze (web + worker), uruchamialny jako aplikacja TrueNAS, z jednym kontem, tokenowym logowaniem i health-checkiem.

**Architecture:** Monolit Django z DRF; SQLite (WAL) na wolumenie `/data`; biblioteka ROMów montowana read-only pod `/library`; taski w tle przez framework Tasks (Django 6) z backendem DB z pakietu `django-tasks` i osobnym procesem workera.

**Tech Stack:** Python 3.13, Django 6.x, djangorestframework, django-tasks, gunicorn, pytest + pytest-django, Docker + compose.

**Spec:** `docs/superpowers/specs/2026-09-01-droplet-design.md`

## Global Constraints

- Konfiguracja wyłącznie przez env: `LIBRARY_ROOT` (default `/library`), `DATA_DIR` (default `/data`), `DJANGO_SECRET_KEY`, `DJANGO_ALLOWED_HOSTS` (CSV), `DJANGO_DEBUG` (`0`/`1`), `DROPLET_ADMIN_USER`, `DROPLET_ADMIN_PASSWORD`.
- SQLite w `{DATA_DIR}/db.sqlite3`, tryb WAL, `busy_timeout=5000` (web i worker piszą równolegle).
- Każdy endpoint poza `/api/health/` i `/api/auth/token/` wymaga `TokenAuthentication` (globalny default DRF `IsAuthenticated`).
- JSON w snake_case (defaulty DRF, bez kamelizacji).
- Testy: `pytest` z `pytest-django`; w testach backend Tasks = `django_tasks.backends.immediate.ImmediateBackend`.
- **Pokrycie 100%**: `pytest` odpalany z `--cov --cov-fail-under=100` (konfiguracja w Task 1); wyłączenia tylko techniczne (migracje, settings, manage.py, wsgi, katalog `e2e/`). Bramka obowiązuje przy zamykaniu KAŻDEGO zadania — kod bez testu nie przechodzi.
- **E2E**: automatyczna suita `backend/e2e/` (pytest + requests) uruchamiana skryptem `scripts/e2e_backend.sh` przeciwko realnemu deploymentowi z docker compose; e2e nie liczy się do pokrycia (`--no-cov`). Zielone e2e = kryterium zamknięcia milestone'u.
- Commity po każdym zadaniu; komunikaty `feat:`/`test:`/`chore:` po angielsku.

---

### Task 1: Szkielet projektu Django + settings z env

**Files:**
- Create: `backend/requirements.txt`, `backend/manage.py`, `backend/droplet/__init__.py`, `backend/droplet/settings.py`, `backend/droplet/urls.py`, `backend/droplet/wsgi.py`, `backend/pytest.ini`, `backend/.coveragerc`, `backend/conftest.py`, `.gitignore`
- Test: `backend/core/tests/test_settings.py` (powstanie z appem `core` — patrz kroki)

**Interfaces:**
- Produces: pakiet projektu `droplet` z `settings.py` czytającym env wg Global Constraints; stałe `settings.LIBRARY_ROOT: Path` i `settings.DATA_DIR: Path`; app `core` zarejestrowany w `INSTALLED_APPS`.

- [ ] **Step 1: Środowisko i zależności**

```bash
mkdir -p backend && cd backend
python3.13 -m venv .venv && source .venv/bin/activate
cat > requirements.txt <<'EOF'
Django>=6.0,<6.1
djangorestframework>=3.16
django-tasks>=0.8
gunicorn>=23.0
requests>=2.32
pytest>=8.0
pytest-django>=4.9
pytest-cov>=5.0
EOF
pip install -r requirements.txt
django-admin startproject droplet .
python manage.py startapp core
mkdir -p core/tests && touch core/tests/__init__.py && rm core/tests.py
```

Do `/.gitignore` w korzeniu repo:

```
.venv/
__pycache__/
*.pyc
db.sqlite3*
/data/
```

- [ ] **Step 2: Napisz settings czytające env**

Zastąp wygenerowane `backend/droplet/settings.py` (kluczowe fragmenty — reszta jak wygenerował Django):

```python
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "dev-only-insecure-key")
DEBUG = os.environ.get("DJANGO_DEBUG", "0") == "1"
ALLOWED_HOSTS = [h for h in os.environ.get("DJANGO_ALLOWED_HOSTS", "*").split(",") if h]

LIBRARY_ROOT = Path(os.environ.get("LIBRARY_ROOT", "/library"))
DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "rest_framework.authtoken",
    "django_tasks",
    "django_tasks.backends.database",
    "core",
]

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": DATA_DIR / "db.sqlite3",
        "OPTIONS": {
            "init_command": "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;",
            "transaction_mode": "IMMEDIATE",
        },
    }
}

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework.authentication.TokenAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
    "DEFAULT_THROTTLE_RATES": {"login": "10/hour"},
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 60,
}

TASKS = {
    "default": {"BACKEND": "django_tasks.backends.database.DatabaseBackend"}
}

STATIC_URL = "static/"
STATIC_ROOT = DATA_DIR / "static"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
```

Uwaga wykonawcza: jeśli nazwy modułów `django_tasks` różnią się w zainstalowanej wersji, sprawdź `pip show django-tasks` + dokumentację (context7) i popraw ścieżki backendu — reszta planu zakłada powyższe.

- [ ] **Step 3: Konfiguracja pytest + settings testowe**

`backend/pytest.ini`:

```ini
[pytest]
DJANGO_SETTINGS_MODULE = droplet.settings_test
python_files = test_*.py
norecursedirs = e2e .venv
addopts = --cov --cov-fail-under=100
```

`backend/.coveragerc` (wyłączenia WYŁĄCZNIE techniczne — logiki się nie wyłącza):

```ini
[run]
source = .
omit =
    */migrations/*
    droplet/settings.py
    droplet/settings_test.py
    droplet/wsgi.py
    droplet/asgi.py
    manage.py
    conftest.py
    e2e/*
    .venv/*

[report]
exclude_lines =
    pragma: no cover
    if TYPE_CHECKING:
```

`backend/droplet/settings_test.py`:

```python
from .settings import *  # noqa

DATA_DIR = BASE_DIR / ".test-data"
DATA_DIR.mkdir(exist_ok=True)
DATABASES["default"]["NAME"] = ":memory:"
TASKS = {"default": {"BACKEND": "django_tasks.backends.immediate.ImmediateBackend"}}
LIBRARY_ROOT = BASE_DIR / ".test-library"
```

`backend/conftest.py`:

```python
import pytest  # noqa: F401
```

- [ ] **Step 4: Napisz test smoke settings**

`backend/core/tests/test_settings.py`:

```python
from pathlib import Path

from django.conf import settings


def test_paths_are_pathlib():
    assert isinstance(settings.LIBRARY_ROOT, Path)
    assert isinstance(settings.DATA_DIR, Path)


def test_drf_defaults_require_auth():
    assert (
        "rest_framework.permissions.IsAuthenticated"
        in settings.REST_FRAMEWORK["DEFAULT_PERMISSION_CLASSES"]
    )
```

- [ ] **Step 5: Uruchom testy i check**

Run: `cd backend && pytest core/tests/test_settings.py -v && python manage.py check`
Expected: 2 testy PASS, check bez błędów.

- [ ] **Step 6: Commit**

```bash
git add backend .gitignore
git commit -m "feat: scaffold Django project with env-driven settings"
```

---

### Task 2: Health endpoint (bez auth)

**Files:**
- Create: `backend/core/views.py` (nadpisz wygenerowany), `backend/core/urls.py`
- Modify: `backend/droplet/urls.py`
- Test: `backend/core/tests/test_health.py`

**Interfaces:**
- Produces: `GET /api/health/` → `200 {"status": "ok", "api_version": 1}` bez uwierzytelnienia. Prefiks `/api/` dla wszystkich endpointów (include `core.urls` w `droplet/urls.py`).

- [ ] **Step 1: Napisz failing test**

`backend/core/tests/test_health.py`:

```python
import pytest


@pytest.mark.django_db
def test_health_requires_no_auth(client):
    resp = client.get("/api/health/")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "api_version": 1}
```

- [ ] **Step 2: Uruchom test — ma failować**

Run: `pytest core/tests/test_health.py -v`
Expected: FAIL (404).

- [ ] **Step 3: Implementacja**

`backend/core/views.py`:

```python
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response


@api_view(["GET"])
@authentication_classes([])
@permission_classes([])
def health(request):
    return Response({"status": "ok", "api_version": 1})
```

`backend/core/urls.py`:

```python
from django.urls import path

from . import views

urlpatterns = [
    path("health/", views.health, name="health"),
]
```

`backend/droplet/urls.py`:

```python
from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/", include("core.urls")),
]
```

- [ ] **Step 4: Testy zielone**

Run: `pytest core/tests/test_health.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/core backend/droplet/urls.py
git commit -m "feat: add unauthenticated health endpoint"
```

---

### Task 3: Komenda createinitialuser

**Files:**
- Create: `backend/core/management/__init__.py`, `backend/core/management/commands/__init__.py`, `backend/core/management/commands/createinitialuser.py`
- Test: `backend/core/tests/test_createinitialuser.py`

**Interfaces:**
- Produces: `python manage.py createinitialuser` — tworzy superusera z env `DROPLET_ADMIN_USER`/`DROPLET_ADMIN_PASSWORD`; idempotentna (drugi bieg nic nie zmienia); brak env = wyraźny błąd.

- [ ] **Step 1: Napisz failing testy**

`backend/core/tests/test_createinitialuser.py`:

```python
import pytest
from django.contrib.auth.models import User
from django.core.management import CommandError, call_command


@pytest.mark.django_db
def test_creates_superuser_from_env(monkeypatch):
    monkeypatch.setenv("DROPLET_ADMIN_USER", "jan")
    monkeypatch.setenv("DROPLET_ADMIN_PASSWORD", "sekret123")
    call_command("createinitialuser")
    user = User.objects.get(username="jan")
    assert user.is_superuser and user.check_password("sekret123")


@pytest.mark.django_db
def test_idempotent(monkeypatch):
    monkeypatch.setenv("DROPLET_ADMIN_USER", "jan")
    monkeypatch.setenv("DROPLET_ADMIN_PASSWORD", "sekret123")
    call_command("createinitialuser")
    call_command("createinitialuser")
    assert User.objects.count() == 1


@pytest.mark.django_db
def test_missing_env_raises(monkeypatch):
    monkeypatch.delenv("DROPLET_ADMIN_USER", raising=False)
    with pytest.raises(CommandError):
        call_command("createinitialuser")
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `pytest core/tests/test_createinitialuser.py -v`
Expected: FAIL (unknown command).

- [ ] **Step 3: Implementacja**

`backend/core/management/commands/createinitialuser.py`:

```python
import os

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "Create the single Droplet user from env (idempotent)."

    def handle(self, *args, **options):
        username = os.environ.get("DROPLET_ADMIN_USER")
        password = os.environ.get("DROPLET_ADMIN_PASSWORD")
        if not username or not password:
            raise CommandError("Set DROPLET_ADMIN_USER and DROPLET_ADMIN_PASSWORD")
        if User.objects.filter(username=username).exists():
            self.stdout.write("User already exists, skipping")
            return
        User.objects.create_superuser(username=username, password=password)
        self.stdout.write(self.style.SUCCESS(f"Created user {username}"))
```

- [ ] **Step 4: Testy zielone**

Run: `pytest core/tests/test_createinitialuser.py -v` — PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/core/management backend/core/tests/test_createinitialuser.py
git commit -m "feat: add idempotent createinitialuser command"
```

---

### Task 4: Logowanie tokenem + /api/me/ + throttling

**Files:**
- Modify: `backend/core/views.py`, `backend/core/urls.py`
- Test: `backend/core/tests/test_auth.py`

**Interfaces:**
- Produces: `POST /api/auth/token/` `{username, password}` → `200 {"token": "..."}` (throttle scope `login`), złe dane → `400`; `GET /api/me/` z nagłówkiem `Authorization: Token <t>` → `200 {"username": ...}`, bez tokenu → `401`. To jest kontrakt logowania dla aplikacji Flutter (M4).

- [ ] **Step 1: Napisz failing testy**

`backend/core/tests/test_auth.py`:

```python
import pytest
from django.contrib.auth.models import User
from rest_framework.test import APIClient


@pytest.fixture
def user(db):
    return User.objects.create_user(username="jan", password="sekret123")


def test_token_for_valid_credentials(user):
    resp = APIClient().post(
        "/api/auth/token/", {"username": "jan", "password": "sekret123"}
    )
    assert resp.status_code == 200
    assert "token" in resp.json()


def test_bad_credentials_rejected(user):
    resp = APIClient().post(
        "/api/auth/token/", {"username": "jan", "password": "zle"}
    )
    assert resp.status_code == 400


def test_me_with_token(user):
    token = APIClient().post(
        "/api/auth/token/", {"username": "jan", "password": "sekret123"}
    ).json()["token"]
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Token {token}")
    resp = client.get("/api/me/")
    assert resp.status_code == 200
    assert resp.json() == {"username": "jan"}


def test_me_without_token_is_401(db):
    assert APIClient().get("/api/me/").status_code == 401


def test_login_view_declares_throttle_scope():
    from core.views import ObtainTokenView

    assert ObtainTokenView.throttle_scope == "login"
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `pytest core/tests/test_auth.py -v` — FAIL (404 / import error).

- [ ] **Step 3: Implementacja**

Dopisz do `backend/core/views.py`:

```python
from rest_framework.authtoken.views import ObtainAuthToken
from rest_framework.throttling import ScopedRateThrottle


class ObtainTokenView(ObtainAuthToken):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "login"


@api_view(["GET"])
def me(request):
    return Response({"username": request.user.username})
```

Do `backend/core/urls.py` dopisz ścieżki:

```python
    path("auth/token/", views.ObtainTokenView.as_view(), name="obtain-token"),
    path("me/", views.me, name="me"),
```

- [ ] **Step 4: Testy zielone**

Run: `pytest core/tests/test_auth.py -v` — PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/core
git commit -m "feat: token login with throttle scope and /api/me endpoint"
```

---

### Task 5: Framework Tasks działa end-to-end

**Files:**
- Create: `backend/core/tasks.py`
- Test: `backend/core/tests/test_tasks.py`

**Interfaces:**
- Produces: wzorzec definiowania tasków (`from django.tasks import task`; `@task()` na funkcji; `fn.enqueue(...)`) używany przez skaner (M1) i okładki (M2). Task demonstracyjny `core.tasks.ping` zwraca `"pong"`.

- [ ] **Step 1: Napisz failing test**

`backend/core/tests/test_tasks.py`:

```python
import pytest

from core.tasks import ping


@pytest.mark.django_db
def test_ping_enqueues_and_runs_immediately():
    result = ping.enqueue()
    assert result.status.name == "SUCCEEDED"
    assert result.return_value == "pong"
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `pytest core/tests/test_tasks.py -v` — FAIL (no module core.tasks).

- [ ] **Step 3: Implementacja**

`backend/core/tasks.py`:

```python
from django.tasks import task


@task()
def ping() -> str:
    return "pong"
```

Uwaga wykonawcza: jeśli import `from django.tasks import task` nie istnieje w zainstalowanym Django, użyj `from django_tasks import task` i popraw ten plik oraz test — pozostała część planów używa tego samego importu co tutaj.

- [ ] **Step 4: Testy zielone + migracje django_tasks**

Run: `python manage.py makemigrations --check --dry-run || true; python manage.py migrate --plan | head; pytest core/tests/test_tasks.py -v`
Expected: test PASS; w `migrate --plan` widoczne migracje `django_tasks`.

- [ ] **Step 5: Commit**

```bash
git add backend/core/tasks.py backend/core/tests/test_tasks.py
git commit -m "feat: wire Django tasks framework with demo task"
```

---

### Task 6: Docker (web + worker) i compose

**Files:**
- Create: `backend/Dockerfile`, `backend/entrypoint.sh`, `docker-compose.yml`, `backend/.dockerignore`

**Interfaces:**
- Produces: obraz `droplet-backend`; compose z serwisami `web` (gunicorn :8000) i `worker` (`manage.py db_worker`); wolumeny `droplet-data` → `/data` i bind `${LIBRARY_PATH}` → `/library:ro`; healthcheck na `/api/health/`. Entrypoint web robi `migrate` + `createinitialuser` + `collectstatic`.

- [ ] **Step 1: Dockerfile**

`backend/Dockerfile`:

```dockerfile
FROM python:3.13-slim AS base
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN chmod +x entrypoint.sh
EXPOSE 8000
ENTRYPOINT ["./entrypoint.sh"]
CMD ["web"]
```

`backend/.dockerignore`:

```
.venv
.test-data
.test-library
__pycache__
```

`backend/entrypoint.sh`:

```bash
#!/bin/sh
set -e
if [ "$1" = "web" ]; then
  python manage.py migrate --noinput
  python manage.py createinitialuser
  python manage.py collectstatic --noinput
  exec gunicorn droplet.wsgi:application --bind 0.0.0.0:8000 --workers 2 --timeout 120
elif [ "$1" = "worker" ]; then
  exec python manage.py db_worker
else
  exec "$@"
fi
```

- [ ] **Step 2: docker-compose.yml (korzeń repo)**

```yaml
services:
  web:
    build: ./backend
    command: ["web"]
    ports: ["8000:8000"]
    environment: &env
      DJANGO_SECRET_KEY: ${DJANGO_SECRET_KEY:?set me}
      DJANGO_ALLOWED_HOSTS: ${DJANGO_ALLOWED_HOSTS:-*}
      DROPLET_ADMIN_USER: ${DROPLET_ADMIN_USER:?set me}
      DROPLET_ADMIN_PASSWORD: ${DROPLET_ADMIN_PASSWORD:?set me}
    volumes:
      - droplet-data:/data
      - ${LIBRARY_PATH:?set me}:/library:ro
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request;urllib.request.urlopen('http://localhost:8000/api/health/')"]
      interval: 30s
      timeout: 5s
      retries: 3
  worker:
    build: ./backend
    command: ["worker"]
    environment: *env
    volumes:
      - droplet-data:/data
      - ${LIBRARY_PATH:?set me}:/library:ro
    depends_on: [web]
volumes:
  droplet-data:
```

- [ ] **Step 3: Weryfikacja lokalna**

```bash
export DJANGO_SECRET_KEY=$(python -c 'import secrets;print(secrets.token_urlsafe(50))')
export DROPLET_ADMIN_USER=jan DROPLET_ADMIN_PASSWORD=sekret123
export LIBRARY_PATH=$PWD/backend/.test-library && mkdir -p $LIBRARY_PATH
docker compose up --build -d
sleep 5
curl -sf http://localhost:8000/api/health/
curl -sf -X POST http://localhost:8000/api/auth/token/ -d "username=jan&password=sekret123"
docker compose ps   # oba serwisy healthy/running
docker compose down
```

Expected: health zwraca JSON, token się wystawia, worker działa bez crash-loopa.

- [ ] **Step 4: Commit**

```bash
git add backend/Dockerfile backend/entrypoint.sh backend/.dockerignore docker-compose.yml
git commit -m "feat: dockerize backend with web and worker services"
```

---

### Task 7: Dokumentacja wdrożenia na TrueNAS

**Files:**
- Create: `docs/deploy.md`

**Interfaces:**
- Produces: instrukcja krok po kroku instalacji jako custom app (Docker Compose) na TrueNAS SCALE; sekcja o nocnym skanie przez cron (wykorzysta ją M1).

- [ ] **Step 1: Napisz docs/deploy.md**

Zawartość (pełny tekst do napisania wg tego szkieletu, po polsku):

1. Wymagania: TrueNAS SCALE z Apps (Docker), dataset z ROMami (np. `/mnt/tank/roms`), dataset na dane aplikacji (np. `/mnt/tank/apps/droplet`).
2. Instalacja: Apps → Discover → Custom App → Install via YAML → wklej `docker-compose.yml` z podmienionym `LIBRARY_PATH` na ścieżkę datasetu i `droplet-data` na hostPath datasetu danych; ustaw env (`DJANGO_SECRET_KEY` — jak wygenerować, user/hasło).
3. Pierwsze uruchomienie: sprawdzenie `http://<ip-nas>:8000/api/health/`, logowanie do `/admin/`.
4. Aktualizacja: `docker compose build && up -d` / re-deploy appki po nowym obrazie.
5. Nocny skan (od M1): System Settings → Advanced → Cron Jobs → `docker exec <kontener-web> python manage.py scan` codziennie 03:00.
6. Wystawienie na świat: poza zakresem — reverse proxy użytkownika; na razie aplikacja mobilna łączy się po `http://<ip-nas>:8000`.
7. Backup: dataset danych (`/data`) zawiera DB i cache okładek; ROMy są read-only i nie są modyfikowane.

- [ ] **Step 2: Commit**

```bash
git add docs/deploy.md
git commit -m "docs: TrueNAS deployment guide"
```

---

### Task 8: Harness e2e + testy e2e M0

**Files:**
- Create: `docker-compose.e2e.yml`, `scripts/e2e_backend.sh`, `backend/e2e/__init__.py`, `backend/e2e/conftest.py`, `backend/e2e/test_health_auth.py`, `backend/e2e/fixture-library/.gitkeep`

**Interfaces:**
- Produces (infrastruktura używana przez e2e wszystkich kolejnych milestone'ów):
  - `docker-compose.e2e.yml` — override: `LIBRARY_PATH=./backend/e2e/fixture-library`, świeży wolumen danych (`droplet-e2e-data`), stały user/hasło `e2e`/`e2e-pass-123`, port 8800.
  - `scripts/e2e_backend.sh` — `compose up -d --build` z overridem → czeka na health (max 60 s) → `pytest e2e -v --no-cov` → `compose down -v`; exit code z pytest.
  - `backend/e2e/conftest.py` — fixtures: `base_url` (env `E2E_BASE_URL`, default `http://localhost:8800`), `token` (login przez API), `auth` (dict nagłówków).

- [ ] **Step 1: Napisz failing testy e2e**

`backend/e2e/conftest.py`:

```python
import os

import pytest
import requests


@pytest.fixture(scope="session")
def base_url() -> str:
    return os.environ.get("E2E_BASE_URL", "http://localhost:8800")


@pytest.fixture(scope="session")
def token(base_url) -> str:
    resp = requests.post(
        f"{base_url}/api/auth/token/",
        data={"username": "e2e", "password": "e2e-pass-123"},
        timeout=10,
    )
    resp.raise_for_status()
    return resp.json()["token"]


@pytest.fixture(scope="session")
def auth(token) -> dict:
    return {"Authorization": f"Token {token}"}
```

`backend/e2e/test_health_auth.py`:

```python
import requests


def test_health_open(base_url):
    resp = requests.get(f"{base_url}/api/health/", timeout=10)
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_me_requires_token(base_url):
    assert requests.get(f"{base_url}/api/me/", timeout=10).status_code == 401


def test_me_with_token(base_url, auth):
    resp = requests.get(f"{base_url}/api/me/", headers=auth, timeout=10)
    assert resp.status_code == 200
    assert resp.json()["username"] == "e2e"


def test_bad_login_rejected(base_url):
    resp = requests.post(
        f"{base_url}/api/auth/token/",
        data={"username": "e2e", "password": "zle"},
        timeout=10,
    )
    assert resp.status_code == 400
```

- [ ] **Step 2: Napisz harness**

`docker-compose.e2e.yml`:

```yaml
services:
  web:
    ports: !override ["8800:8000"]
    environment:
      DJANGO_SECRET_KEY: e2e-secret
      DROPLET_ADMIN_USER: e2e
      DROPLET_ADMIN_PASSWORD: e2e-pass-123
    volumes: !override
      - droplet-e2e-data:/data
      - ./backend/e2e/fixture-library:/library:ro
  worker:
    environment:
      DJANGO_SECRET_KEY: e2e-secret
      DROPLET_ADMIN_USER: e2e
      DROPLET_ADMIN_PASSWORD: e2e-pass-123
    volumes: !override
      - droplet-e2e-data:/data
      - ./backend/e2e/fixture-library:/library:ro
volumes:
  droplet-e2e-data:
```

`scripts/e2e_backend.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.e2e.yml"
cleanup() { $COMPOSE down -v; }
trap cleanup EXIT
$COMPOSE up -d --build
for i in $(seq 1 60); do
  curl -sf http://localhost:8800/api/health/ >/dev/null && break
  sleep 1
done
cd backend && pytest e2e -v --no-cov
```

`chmod +x scripts/e2e_backend.sh`. Uwaga: `!override` wymaga compose >= 2.24; przy starszym — zamiast override zdubluj pełne definicje serwisów w pliku e2e.

- [ ] **Step 3: Uruchom e2e**

Run: `./scripts/e2e_backend.sh`
Expected: 4 testy PASS, kontenery posprzątane po biegu.

- [ ] **Step 4: Commit**

```bash
git add docker-compose.e2e.yml scripts/e2e_backend.sh backend/e2e
git commit -m "feat: e2e harness with compose override and auth e2e tests"
```

---

### Task 9: Pełny bieg testów, bramka pokrycia i sanity końcowe M0

**Files:**
- Modify: brak (weryfikacja)

- [ ] **Step 1: Całość testów unit + bramka 100%**

Run: `cd backend && pytest -v`
Expected: wszystkie testy PASS i `Required test coverage of 100% reached` (jeśli nie — dopisz brakujące testy, nie wyłączenia).

- [ ] **Step 2: E2E**

Run: `./scripts/e2e_backend.sh`
Expected: PASS.

- [ ] **Step 3: Ręczny sanity-check kryteriów M0**

- `docker compose up` → `/api/health/` 200 bez auth.
- `GET /api/me/` bez tokenu → 401; z tokenem → 200.
- `/admin/` przyjmuje login z env.

- [ ] **Step 4: Commit (jeśli były poprawki)**

```bash
git add -A && git commit -m "chore: M0 wrap-up fixes" || echo "nothing to commit"
```
