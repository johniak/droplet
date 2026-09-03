# Droplet

Prywatny „Steam dla ROM-ów": serwer na TrueNAS indeksuje Twoją kolekcję gier,
a aplikacja na Androida pokazuje ją jako bibliotekę z okładkami i pobiera gry na
telefon. Jedno konto, jedna sieć domowa, zero chmury.

> **English:** a self-hosted, single-user ROM library. The Django backend runs
> on a NAS and scans a read-only ROM folder; the Flutter Android app browses the
> library, downloads games and tracks what is installed on the device. Docs are
> in Polish; the code and API are English. Bring your own legally owned dumps —
> the repo ships no game data.

## Co robi

- **Serwer (Django 6 + DRF)**: skanuje `<biblioteka>/<system>/<Nazwa gry>/`,
  rozpoznaje role plików (baza, aktualizacja, DLC, płyty, playlisty), dopasowuje
  okładki z [libretro-thumbnails](https://github.com/libretro-thumbnails) i
  wystawia REST API z tokenem. Panel admina do ręcznych poprawek.
- **Aplikacja (Flutter, Android)**: półki per system, wyszukiwanie, szczegóły gry,
  pobieranie w tle z wznawianiem, skan urządzenia („co już mam"), ustawienia
  katalogów per system.

## Szybki start

Obraz backendu jest na Docker Hubie jako
[`johniak/droplet-backend`](https://hub.docker.com/r/johniak/droplet-backend).

```bash
git clone https://github.com/johniak/droplet.git
cd droplet
cat > .env <<ENV
DJANGO_SECRET_KEY=$(python3 -c 'import secrets;print(secrets.token_urlsafe(50))')
DROPLET_ADMIN_USER=jan
DROPLET_ADMIN_PASSWORD=zmien-mnie
LIBRARY_PATH=/sciezka/do/romow
ENV
docker compose up -d
curl http://localhost:8000/api/health/
```

Aplikację budujesz z `app/` przez `flutter build apk --release` i w niej wpisujesz
adres serwera. Wdrożenie na TrueNAS SCALE, układ biblioteki, aktualizacje i backup:
[`docs/deploy.md`](docs/deploy.md).

## Struktura repo

| Katalog | Zawartość |
|---|---|
| `backend/` | Django: `library` (skaner, modele, API), `covers` (okładki), `core` (auth, health), `e2e` (testy na żywym stacku) |
| `app/` | Flutter: `lib/core` (API, sesja, pobieranie, skan urządzenia), `lib/features` (ekrany), `integration_test` |
| `docs/` | Wdrożenie, specyfikacje i plany milestone'ów (`docs/superpowers/`) |
| `scripts/` | Bramki jakości: pokrycie aplikacji, e2e backendu i aplikacji, smoke |

## Rozwój

Twarde bramki: **100% pokrycia** testami po obu stronach i automatyczne e2e.

```bash
# backend
cd backend && python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python -m pytest              # --cov-fail-under=100 w pytest.ini

# aplikacja
cd app && flutter pub get
./scripts/check_coverage_app.sh         # z katalogu głównego repo

# e2e (Docker + emulator Androida)
./scripts/e2e_backend.sh
E2E_SERVER=http://10.0.2.2:8800 ./scripts/e2e_app.sh
```

Wersje obrazu na Docker Hubie buduje GitHub Actions
(`.github/workflows/docker.yml`): `edge` z gałęzi `main`, `X.Y.Z`, `X.Y` i
`latest` z tagów `vX.Y.Z`.

## Licencja

[MIT](LICENSE). Droplet nie zawiera ani nie rozpowszechnia żadnych gier, BIOS-ów
ani okładek; okładki pobiera w czasie działania z publicznego repozytorium
libretro-thumbnails na Twoje własne urządzenie.
