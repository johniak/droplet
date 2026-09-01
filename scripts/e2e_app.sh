#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
E2E_SERVER=${E2E_SERVER:?ustaw np. E2E_SERVER=http://192.168.1.10:8800 (IP hosta widoczne z telefonu)}
# te same zmienne co w scripts/e2e_backend.sh — bazowy compose ich wymaga
export LIBRARY_PATH="$PWD/backend/e2e/fixture-library"
export DJANGO_SECRET_KEY=e2e-secret
export DROPLET_ADMIN_USER=e2e
export DROPLET_ADMIN_PASSWORD=e2e-pass-123
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.e2e.yml"
cleanup() { $COMPOSE down -v; }
trap cleanup EXIT
$COMPOSE up -d --build
for i in $(seq 1 60); do curl -sf localhost:8800/api/health/ >/dev/null && break; sleep 1; done
curl -sf localhost:8800/api/health/ >/dev/null || { echo "backend e2e nie wstał"; exit 1; }
adb devices | grep -qw device || { echo "brak podłączonego urządzenia Android"; exit 1; }
# E2E=true: aplikacja nie pokazuje systemowych dialogów uprawnień (M5) — test nie umie ich kliknąć
cd app && flutter test integration_test \
  --dart-define=E2E_SERVER="$E2E_SERVER" --dart-define=E2E=true
