# Droplet

A self-hosted, single-user "Steam for ROMs". The server runs on your NAS and
indexes your game collection; the Android app shows it as a library with cover
art and downloads games to the phone. One account, one home network, no cloud.

Droplet ships no game data. Bring your own legally owned dumps.

## What it does

- **Server (Django 6 + DRF)**: scans `<library>/<system>/<Game name>/`,
  recognises file roles (base, update, DLC, discs, playlists), matches cover art
  from [libretro-thumbnails](https://github.com/libretro-thumbnails) and exposes
  a token-authenticated REST API. The Django admin is there for manual fixes.
- **App (Flutter, Android)**: shelves per system, search, game details,
  resumable background downloads, a device scan ("what do I already have"),
  per-system folder overrides.

## Quick start

The backend image is on Docker Hub as
[`johniak/droplet-backend`](https://hub.docker.com/r/johniak/droplet-backend)
(`linux/amd64` and `linux/arm64`).

```bash
git clone https://github.com/johniak/droplet.git
cd droplet
cat > .env <<ENV
DJANGO_SECRET_KEY=$(python3 -c 'import secrets;print(secrets.token_urlsafe(50))')
DROPLET_ADMIN_USER=jan
DROPLET_ADMIN_PASSWORD=change-me
LIBRARY_PATH=/path/to/your/roms
ENV
docker compose up -d
curl http://localhost:8000/api/health/
```

Build the app from `app/` with `flutter build apk --release` and enter the
server address on first launch. TrueNAS SCALE deployment, library layout,
updates and backups are covered in [`docs/deploy.md`](docs/deploy.md)
(currently in Polish).

## Library layout

A folder is a game. Under each system folder, every sub-folder is one library
entry and everything inside it belongs to that game. Files lying directly in a
system folder are reported in the admin as "loose" and do not create games.

```
roms/
├── snes/
│   └── Super Mario World (USA)/
│       └── Super Mario World (USA).sfc
├── switch/
│   └── Hollow Knight/                      # base, update and DLC together
│       ├── Hollow Knight [0100633007D48000][v0].nsp
│       └── Hollow Knight [UPD][0100633007D48800][v196608].nsp
└── psx/
    └── Final Fantasy VII (USA)/            # sub-folders are allowed
        ├── Final Fantasy VII (USA).m3u
        ├── disc1/ …
        └── disc2/ …
```

The app mirrors the same layout on the phone:
`<ROM folder>/<system>/<Game name>/<files>`.

## Repository layout

| Directory | Contents |
|---|---|
| `backend/` | Django: `library` (scanner, models, API), `covers` (cover art), `core` (auth, health), `e2e` (tests against a live stack) |
| `app/` | Flutter: `lib/core` (API, session, downloads, device scan), `lib/features` (screens), `integration_test` |
| `docs/` | Deployment guide, design specs and milestone plans (`docs/superpowers/`) |
| `scripts/` | Quality gates: app coverage, backend and app e2e, smoke |

## Development

Hard gates: **100% test coverage** on both sides plus automated e2e suites.

```bash
# backend
cd backend && python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python -m pytest              # --cov-fail-under=100 lives in pytest.ini

# app
cd app && flutter pub get
./scripts/check_coverage_app.sh         # run from the repo root

# e2e (Docker + Android emulator)
./scripts/e2e_backend.sh
E2E_SERVER=http://10.0.2.2:8800 ./scripts/e2e_app.sh
```

Docker Hub images are built by GitHub Actions (`.github/workflows/docker.yml`):
`edge` from `main`; `X.Y.Z`, `X.Y` and `latest` from `vX.Y.Z` tags.

## License

[MIT](LICENSE). Droplet does not contain or distribute any games, BIOS files or
cover art; covers are fetched at runtime from the public libretro-thumbnails
repository onto your own device.
