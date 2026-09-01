# RALPH-STATUS

Status pętli Ralph budującej Droplet wg planów M0–M6.

## Czeka na Jana

- **M1 Task 11 kroki 2–4 — skan prawdziwej biblioteki na TrueNAS.** Wymaga realnego
  NAS-a z Twoimi ROMami:
  1. `docker compose build && docker compose up -d`, potem
     `docker compose exec web python manage.py scan`.
  2. Porównaj liczby gier per system w adminie z zawartością katalogów „na oko";
     rozjazdy (złe grupowanie Switcha, nieznane katalogi) popraw w adminie albo
     dopisz aliasy do `backend/library/scanner/systems_map.py`.
  3. Drugi `manage.py scan` musi dać `+0 ~0 -0` (idempotencja na realnych danych).
  4. Ustaw nocny cron na TrueNAS wg `docs/deploy.md` §5
     (`docker exec <kontener-web> python manage.py scan`, 03:00).

## Blokery

(brak)

## Rozjazdy planu z rzeczywistością

- **M0 Task 1 — backend Tasks**: `django-tasks` 0.12+ nie zawiera już backendu DB
  (`django_tasks.backends.database` zostało wydzielone do pakietu `django-tasks-db`),
  a Django 6.0 ma wbudowany `django.tasks`. Rozwiązanie minimalne: w
  `requirements.txt` jest `django-tasks-db>=0.13` zamiast `django-tasks`,
  w `INSTALLED_APPS` jest `django_tasks_db`, `TASKS.default.BACKEND` =
  `django_tasks_db.DatabaseBackend`, a w testach
  `django.tasks.backends.immediate.ImmediateBackend`. Taski definiujemy przez
  `from django.tasks import task`. Komenda workera `manage.py db_worker` pochodzi
  z `django-tasks-db` (bez zmian względem planu).
- **M0 Task 1 — bramka pokrycia**: żeby `--cov-fail-under=100` przechodziło już przy
  zamknięciu Task 1, `core/views.py` (pusty stub Django) usunięto (Task 2 tworzy go
  od nowa), a do `core/tests/test_settings.py` dopisano smoke test ładowania
  `ROOT_URLCONF` (`test_root_urlconf_loads`). Żadnych wyłączeń pokrycia poza
  technicznymi z planu.
- **M0 Task 5 — status wyniku taska**: plan zakłada `result.status.name == "SUCCEEDED"`,
  ale w Django 6 / django-tasks 0.12+ status nazywa się `SUCCESSFUL`
  (`TaskResultStatus.SUCCESSFUL`). Test w `core/tests/test_tasks.py` używa poprawnej
  nazwy. Migracje backendu DB pojawiają się pod etykietą aplikacji
  `django_tasks_database` (pakiet `django_tasks_db`).
- **M0 Task 8 — harness e2e**: `docker-compose.yml` wymaga zmiennych
  (`${DJANGO_SECRET_KEY:?set me}` itd.) już na etapie interpolacji, zanim compose
  scali override, więc `scripts/e2e_backend.sh` eksportuje te zmienne przed
  wywołaniem compose'a (i tak nadpisuje je `docker-compose.e2e.yml`). Dodatkowo
  pytest odpalany jest w subshellu, żeby trap `down -v` widział pliki compose'a
  z korzenia repo.
- **Zasada ogólna (od M1 Task 1)**: gdy fragmenty kodu z planu nie są w całości pokryte
  testami z planu (np. metody `__str__` modeli), dopisuję minimalny, prawdziwy test
  zamiast wyłączenia pokrycia. Puste stuby generowane przez `startapp`
  (`library/views.py`) usuwam, bo tworzą je dopiero późniejsze taski.
- **M1 Task 5 — pomijanie ukrytych plików**: plan sprawdza `p.parts` (całą ścieżkę
  absolutną), przez co katalog ukryty gdziekolwiek wyżej w drzewie (np.
  `/home/x/.local/roms`) wyciąłby całą bibliotekę. W implementacji sprawdzam
  `p.relative_to(library_root).parts` — semantyka „ukryte w bibliotece", zgodna
  z intencją planu.
- **M2 Task 3 — scorer fuzzy**: plan każe użyć `fuzz.token_sort_ratio`, ale wtedy jego
  własny test (`"zelda a link to the past"` → „Legend of Zelda, The - A Link to the
  Past (USA)") dostaje 77.4 i nie przechodzi progu 85. Użyłem `fuzz.WRatio`
  (85.5 dla tego przypadku, 64.1 dla kontrprzykładu „wario land 4" — więc próg
  nadal działa). Koszt: WRatio zawyża wynik przy krótkich podciągach (np. samo
  „mario" → 90 dla „super mario world"); łagodzi to reguła exact-match oraz
  ręczne poprawki dopasowania w adminie (Task 6).
- **M2 Task 7 — blokada sieci a e2e**: autouse fixture `_no_network` z `backend/conftest.py`
  (M2 Task 1) obejmowała także `backend/e2e/`, przez co cała suita e2e wywalała się na
  `RuntimeError: Sieć zablokowana`. Rozwiązane nadpisaniem fixture o tej samej nazwie
  w `backend/e2e/conftest.py` (no-op) — blokada dalej działa w testach jednostkowych.
  Dodatkowo `DROPLET_AUTO_COVERS` doszło do `docker-compose.yml` (default `1`),
  `docker-compose.e2e.yml` (`0`) i tabelki env w `docs/deploy.md`.
