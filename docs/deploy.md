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

Gotowy obraz backendu leży na Docker Hubie:
[`johniak/droplet-backend`](https://hub.docker.com/r/johniak/droplet-backend)
(`linux/amd64` i `linux/arm64`). Tagi: `latest` i `X.Y.Z` z wydań, `edge` z
gałęzi `main`. TrueNAS nie buduje obrazów ze źródeł, więc w YAML-u poniżej
używamy `image:`, a nie `build:`.

1. W TrueNAS: **Apps → Discover Apps → Custom App → Install via YAML**.
2. Wklej poniższy YAML, podmieniając ścieżki datasetów i wartości `environment`:

   ```yaml
   services:
     web:
       image: johniak/droplet-backend:latest
       command: ["web"]
       restart: unless-stopped
       ports: ["8000:8000"]
       environment: &env
         DJANGO_SECRET_KEY: "<długi losowy sekret>"
         DJANGO_ALLOWED_HOSTS: "*"
         DROPLET_ADMIN_USER: "<login>"
         DROPLET_ADMIN_PASSWORD: "<hasło>"
         DROPLET_AUTO_COVERS: "1"
       volumes:
         - /mnt/tank/apps/droplet:/data
         - /mnt/tank/roms:/library:ro
       healthcheck:
         test: ["CMD", "python", "-c", "import urllib.request;urllib.request.urlopen('http://localhost:8000/api/health/')"]
         interval: 10s
         timeout: 5s
         retries: 5
         start_period: 30s
     worker:
       image: johniak/droplet-backend:latest
       command: ["worker"]
       restart: unless-stopped
       environment: *env
       volumes:
         - /mnt/tank/apps/droplet:/data
         - /mnt/tank/roms:/library:ro
       depends_on:
         web:
           condition: service_healthy
   ```

   Kontenery działają jako root, więc ACL-e datasetów nie wymagają dodatkowej
   konfiguracji. Dataset z ROM-ami jest montowany tylko do odczytu.

3. Ustaw zmienne środowiskowe (sekcja `environment` obu serwisów):

   | Zmienna | Wartość |
   |---|---|
   | `DJANGO_SECRET_KEY` | długi losowy sekret (patrz niżej) |
   | `DJANGO_ALLOWED_HOSTS` | `*` albo lista hostów po przecinku |
   | `DROPLET_ADMIN_USER` | nazwa Twojego jedynego konta |
   | `DROPLET_ADMIN_PASSWORD` | hasło do tego konta |
   | `DROPLET_AUTO_COVERS` | `1` (domyślnie) — po każdym skanie automatycznie dopasowuj okładki z libretro-thumbnails; `0` wyłącza (backend nie wychodzi wtedy do internetu) |
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

Na TrueNAS: podnieś tag w YAML-u (np. `johniak/droplet-backend:0.4.0`) albo zostaw
`latest` i zrób **Edit → Update** aplikacji; przy `latest` TrueNAS pobierze nowy
obraz, jeśli w ustawieniach appki włączysz „pull images". Migracje bazy wykonają
się automatycznie przy starcie kontenera `web`.

Z repozytorium (compose na dowolnym hoście):

```bash
git pull
docker compose pull      # obraz z Docker Huba
docker compose up -d
# albo lokalny build ze źródeł:
docker compose up -d --build
```

### Aktualizacja do M7 (katalogi per gra)

Migracja `library.0002_folders` nadaje starym grom folder wyliczony z pierwszego
pliku, ale dopiero skan uzgadnia bazę z dyskiem. Po aktualizacji uruchom skan
**dwa razy**:

```bash
docker compose exec web python manage.py scan
docker compose exec web python manage.py scan   # musi dać +0 ~0 -0
```

Pierwszy przebieg przepina pliki do gier wyznaczonych przez katalogi i kasuje
puste, osierocone wpisy; drugi jest już tylko potwierdzeniem, że baza się
zbiegła (`files_created`/`files_updated`/`files_deleted` = 0 we wpisie
`ScanRun`).

Czego się spodziewać:

- **Gry sprzed M7 leżące luzem** (plik bezpośrednio w katalogu systemu) znikają
  z biblioteki, a ich pliki lądują w **„Do uporządkowania"**
  (`/admin/library/loosefile/`). Wrócą jako gry, gdy przeniesiesz je do katalogu
  gry i uruchomisz skan ponownie.
- **Dwie stare gry wskazujące ten sam katalog** (np. `disc1/` i `disc2/` jednej
  gry) scalają się w jedną pozycję — folder jest unikalny, więc bierze go
  pierwsza, a pliki drugiej skan przepina do niej.
- W aplikacji 0.3.0 stary, płaski układ na telefonie pokaże się w
  **Settings → Unknown on device**.
- W **Settings → Folders per system** puste pole znaczy „podkatalog o nazwie
  kodu systemu" — nie kasuje nadpisania na coś pustego. Wartość z separatorem
  (`/`, `\`) albo `..` jest ignorowana: katalog systemu musi zostać wewnątrz
  katalogu ROMów.

## 5. Układ biblioteki (od M7)

Droplet traktuje **katalog jako grę**: pod katalogiem systemu każdy podkatalog to
jedna pozycja w bibliotece, a wszystko w środku (włącznie z podkatalogami) należy
do niej.

```
<biblioteka>/<system>/<Nazwa gry>/<pliki>
```

Przykład:

```
/mnt/tank/roms/
├── snes/
│   └── Super Mario World (USA)/
│       └── Super Mario World (USA).sfc
├── switch/
│   └── Hollow Knight/                      # baza, aktualizacja i DLC razem
│       ├── Hollow Knight [0100633007D48000][v0].nsp
│       ├── Hollow Knight [UPD][0100633007D48800][v196608].nsp
│       └── Hollow Knight [DLC][01006330124CE000][v0].nsp
└── psx/
    └── Final Fantasy VII (USA)/            # podkatalogi są dozwolone
        ├── Final Fantasy VII (USA).m3u
        ├── disc1/
        │   ├── Final Fantasy VII (USA) (Disc 1).cue
        │   └── Final Fantasy VII (USA) (Disc 1).bin
        └── disc2/
            ├── Final Fantasy VII (USA) (Disc 2).cue
            └── Final Fantasy VII (USA) (Disc 2).bin
```

Zasady:

- Nazwa katalogu jest tożsamością gry — zmiana nazwy katalogu to dla Dropletu
  nowa gra (stara zniknie z biblioteki przy kolejnym skanie).
- Aplikacja odtwarza ten sam układ na telefonie:
  `<katalog ROMów>/<system>/<Nazwa gry>/<pliki>`. Środkowy segment bierze się z
  kodu systemu, ale **Settings → Folders per system** potrafią go nadpisać
  (np. `snes` → `SNES`) — wtedy na telefonie jest
  `<katalog ROMów>/SNES/<Nazwa gry>/<pliki>`, a reszta układu bez zmian.
- Pliki leżące **luzem** w katalogu systemu (poza katalogiem gry) nie tworzą gry —
  lądują w adminie pod **„Do uporządkowania"** (`/admin/library/loosefile/`).
  Ile ich jest, pokazuje kolumna „luzem" na liście **systemów**
  (`/admin/library/system/`); pojedynczy skan raportuje swoje w polu
  `loose_files` wpisu `ScanRun`. Przenieś je do katalogu gry i uruchom skan
  ponownie.
- Sidecary (`.srm`, `.sav`, obrazki, `.txt`) w katalogu gry są zapisywane z rolą
  `other` — nie psują rozpoznania roli bazowej.

## 6. Nocny skan biblioteki (od M1)

Skan jest przyrostowy i uruchamiany ręcznie z admina/API, ale warto go odpalać
też co noc:

**System Settings → Advanced → Cron Jobs → Add**

```bash
docker exec <nazwa-kontenera-web> python manage.py scan
```

Harmonogram: codziennie o 03:00. Nazwę kontenera podejrzysz przez `docker ps`
(dla compose'a z repo to `droplet-web-1`).

## 7. Wystawienie na świat

Poza zakresem Dropletu — robi to reverse proxy po Twojej stronie (np. Nginx
Proxy Manager / Traefik z certyfikatem Let's Encrypt). Na razie aplikacja mobilna
łączy się bezpośrednio po `http://<ip-nas>:8000`, adres wpisujesz w ustawieniach
aplikacji.

Uwaga: bez HTTPS token uwierzytelniający leci po sieci otwartym tekstem — używaj
tego wyłącznie w zaufanej sieci lokalnej albo postaw reverse proxy z TLS.

## 8. Backup

- **Do backupu**: dataset danych (`/data`) — zawiera bazę SQLite z całym indeksem
  biblioteki, dopasowaniami okładek i ręcznymi poprawkami oraz cache okładek.
  Backup rób przy zatrzymanej aplikacji albo snapshotem ZFS (SQLite w WAL —
  snapshot datasetu jest spójny).
- **Bez backupu z poziomu Dropletu**: dataset z ROMami jest montowany read-only
  i nigdy nie jest modyfikowany; jego kopie zapasowe zapewniasz osobno.
