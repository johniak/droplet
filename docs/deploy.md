# Wdrożenie Dropletu na TrueNAS SCALE

Dokument opisuje instalację backendu Dropletu jako aplikacji custom (Docker Compose)
na TrueNAS SCALE, pierwsze uruchomienie, aktualizacje i backup.

## 1. Wymagania

- **TrueNAS SCALE** z włączonymi Apps (backend Docker).
- **Dataset z ROMami**, np. `/mnt/tank/roms` — montowany do kontenerów jako
  `/library` w trybie **read-only**. Droplet nigdy nie zapisuje do tego datasetu.
  Katalogi pierwszego poziomu w tym datasecie to systemy (np. `snes/`, `psx/`,
  `switch/`).
- **Dataset na dane aplikacji**, np. `/mnt/tank/apps/droplet` — montowany jako
  `/data`. Trzyma bazę SQLite (`db.sqlite3`), cache okładek (`covers/`) i pliki
  statyczne admina (`static/`).
- Docker Compose w wersji ≥ 2.24 (TrueNAS SCALE 24.10+), jeśli chcesz korzystać
  z plików override (`docker-compose.e2e.yml` używa składni `!override`).

## 2. Instalacja jako Custom App

1. W TrueNAS: **Apps → Discover Apps → Custom App → Install via YAML**.
2. Wklej zawartość `docker-compose.yml` z repozytorium, podmieniając:
   - `${LIBRARY_PATH}` → ścieżka datasetu z ROMami, np. `/mnt/tank/roms`,
   - definicję wolumenu `droplet-data` → bind na dataset danych, np.:

     ```yaml
     volumes:
       droplet-data:
         driver: local
         driver_opts:
           type: none
           o: bind
           device: /mnt/tank/apps/droplet
     ```

3. Ustaw zmienne środowiskowe (sekcja `environment` obu serwisów):

   | Zmienna | Wartość |
   |---|---|
   | `DJANGO_SECRET_KEY` | długi losowy sekret (patrz niżej) |
   | `DJANGO_ALLOWED_HOSTS` | `*` albo lista hostów po przecinku |
   | `DROPLET_ADMIN_USER` | nazwa Twojego jedynego konta |
   | `DROPLET_ADMIN_PASSWORD` | hasło do tego konta |
   | `DJANGO_CSRF_TRUSTED_ORIGINS` | lista origins po przecinku, gdy admin stoi za reverse proxy z HTTPS (np. `https://droplet.example.com`); puste = brak wpisów |

   Sekret wygenerujesz np. tak:

   ```bash
   python3 -c 'import secrets; print(secrets.token_urlsafe(50))'
   ```

   Opcjonalnie: `DJANGO_DEBUG=0` (domyślnie), `LIBRARY_ROOT=/library`,
   `DATA_DIR=/data` — domyślne wartości pasują do compose'a i nie trzeba ich
   ustawiać.

4. Zapisz i zainstaluj aplikację. Wstaną dwa kontenery:
   - `web` — Django + DRF pod gunicornem na porcie 8000,
   - `worker` — proces `manage.py db_worker` wykonujący taski w tle
     (skan biblioteki, pobieranie okładek).

   Oba współdzielą wolumen `/data` (SQLite w trybie WAL) i mają `/library`
   zamontowane read-only.

## 3. Pierwsze uruchomienie

Kontener `web` przy starcie automatycznie robi `migrate`, `createinitialuser`
(idempotentnie, z env) i `collectstatic`.

Sprawdź:

```bash
curl http://<ip-nas>:8000/api/health/
# {"status": "ok", "api_version": 1}

curl -X POST http://<ip-nas>:8000/api/auth/token/ \
  -d "username=<DROPLET_ADMIN_USER>&password=<DROPLET_ADMIN_PASSWORD>"
# {"token": "..."}
```

Panel administracyjny: `http://<ip-nas>:8000/admin/` — logowanie tym samym
kontem z env.

Jeśli `web` nie wstaje, sprawdź logi kontenera: najczęstsze przyczyny to brak
wymaganych zmiennych środowiskowych albo brak praw zapisu do datasetu `/data`.

## 4. Aktualizacja

```bash
git pull
docker compose build
docker compose up -d
```

Na TrueNAS: przebuduj/wypchnij nowy obraz, a następnie zrób **Edit → Update**
(re-deploy) aplikacji. Migracje bazy wykonają się automatycznie przy starcie
kontenera `web`.

## 5. Nocny skan biblioteki (od M1)

Skan jest przyrostowy i uruchamiany ręcznie z admina/API, ale warto go odpalać
też co noc:

**System Settings → Advanced → Cron Jobs → Add**

```bash
docker exec <nazwa-kontenera-web> python manage.py scan
```

Harmonogram: codziennie o 03:00. Nazwę kontenera podejrzysz przez `docker ps`
(dla compose'a z repo to `droplet-web-1`).

## 6. Wystawienie na świat

Poza zakresem Dropletu — robi to reverse proxy po Twojej stronie (np. Nginx
Proxy Manager / Traefik z certyfikatem Let's Encrypt). Na razie aplikacja mobilna
łączy się bezpośrednio po `http://<ip-nas>:8000`, adres wpisujesz w ustawieniach
aplikacji.

Uwaga: bez HTTPS token uwierzytelniający leci po sieci otwartym tekstem — używaj
tego wyłącznie w zaufanej sieci lokalnej albo postaw reverse proxy z TLS.

## 7. Backup

- **Do backupu**: dataset danych (`/data`) — zawiera bazę SQLite z całym indeksem
  biblioteki, dopasowaniami okładek i ręcznymi poprawkami oraz cache okładek.
  Backup rób przy zatrzymanej aplikacji albo snapshotem ZFS (SQLite w WAL —
  snapshot datasetu jest spójny).
- **Bez backupu z poziomu Dropletu**: dataset z ROMami jest montowany read-only
  i nigdy nie jest modyfikowany; jego kopie zapasowe zapewniasz osobno.
