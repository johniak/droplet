#!/usr/bin/env bash
set -euo pipefail
BASE=${1:?usage: smoke.sh http://host:8000 user pass}
USER=${2:?} PASS=${3:?}

TOKEN=$(curl -sf -X POST "$BASE/api/auth/token/" -d "username=$USER&password=$PASS" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
AUTH="Authorization: Token $TOKEN"

echo "== systems =="; curl -sf -H "$AUTH" "$BASE/api/systems/" | python3 -m json.tool | head -20
echo "== games p1 =="; curl -sf -H "$AUTH" "$BASE/api/games/" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["count"],"gier")'

GAME_ID=$(curl -sf -H "$AUTH" "$BASE/api/games/" | python3 -c 'import sys,json;print(json.load(sys.stdin)["results"][0]["id"])')
FILE_ID=$(curl -sf -H "$AUTH" "$BASE/api/games/$GAME_ID/" | python3 -c 'import sys,json;print(json.load(sys.stdin)["files"][0]["id"])')

echo "== download z przerwaniem i wznowieniem =="
curl -sf -H "$AUTH" -r 0-99999 "$BASE/api/files/$FILE_ID/download" -o /tmp/part1
curl -sf -H "$AUTH" -C 100000 "$BASE/api/files/$FILE_ID/download" -o /tmp/part2
cat /tmp/part1 /tmp/part2 > /tmp/full-resumed
curl -sf -H "$AUTH" "$BASE/api/files/$FILE_ID/download" -o /tmp/full-direct
cmp /tmp/full-resumed /tmp/full-direct && echo "RESUME OK"

echo "== auth wymagany =="
test "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/games/")" = "401" && echo "401 OK"
echo "SMOKE PASSED"
