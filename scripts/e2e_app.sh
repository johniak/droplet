#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
E2E_SERVER=${E2E_SERVER:?ustaw np. E2E_SERVER=http://192.168.1.10:8800 (IP hosta widoczne z telefonu)}
# te same zmienne co w scripts/e2e_backend.sh — bazowy compose ich wymaga
export LIBRARY_PATH="$PWD/backend/e2e/fixture-library"
export DJANGO_SECRET_KEY=e2e-secret
export DROPLET_ADMIN_USER=e2e
export DROPLET_ADMIN_PASSWORD=e2e-pass-123
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.e2e.yml"
# cd do app poniżej zmienia cwd skryptu — cleanup musi więc jawnie wrócić do
# $ROOT, inaczej compose nie znajdzie plików po ścieżkach względnych i trap
# cicho nic nie posprząta.
cleanup() { cd "$ROOT" && $COMPOSE down -v; }
trap cleanup EXIT
$COMPOSE up -d --build
for i in $(seq 1 60); do curl -sf localhost:8800/api/health/ >/dev/null && break; sleep 1; done
curl -sf localhost:8800/api/health/ >/dev/null || { echo "backend e2e nie wstał"; exit 1; }
adb devices | grep -qw device || { echo "brak podłączonego urządzenia Android"; exit 1; }
# E2E=true: aplikacja nie pokazuje systemowych dialogów uprawnień (M5) — test nie umie ich kliknąć
# Podshell, żeby `cd app` nie zmieniało cwd tego skryptu (i tak samo trapu).
# E2E_DEVICE: przy kilku podłączonych urządzeniach flutter wymaga wskazania celu
(cd app && flutter test -d "${E2E_DEVICE:-emulator-5554}" integration_test \
  --dart-define=E2E_SERVER="$E2E_SERVER" --dart-define=E2E=true)
