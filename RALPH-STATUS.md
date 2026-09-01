# RALPH-STATUS

Status pętli Ralph budującej Droplet wg planów M0–M6.

## Czeka na Jana

(brak)

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
