import time

import requests


def _first_game_id(base_url, auth) -> int:
    requests.post(f"{base_url}/api/scan/", headers=auth, timeout=10)
    time.sleep(5)
    games = requests.get(f"{base_url}/api/games/", headers=auth, timeout=10)
    if games.status_code == 404:
        # Before M3 there is no game list — the fixture scan creates ids from 1.
        return 1
    return games.json()["results"][0]["id"]


def test_cover_requires_auth(base_url, auth):
    game_id = _first_game_id(base_url, auth)
    resp = requests.get(f"{base_url}/api/games/{game_id}/cover", timeout=10)
    assert resp.status_code == 401


def test_cover_missing_is_404(base_url, auth):
    game_id = _first_game_id(base_url, auth)
    resp = requests.get(
        f"{base_url}/api/games/{game_id}/cover", headers=auth, timeout=10
    )
    assert resp.status_code == 404  # DROPLET_AUTO_COVERS=0 in e2e → no covers
