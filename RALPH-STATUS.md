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
