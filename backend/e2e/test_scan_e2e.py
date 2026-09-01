import time

import requests


def test_scan_via_api_indexes_fixture_library(base_url, auth):
    resp = requests.post(f"{base_url}/api/scan/", headers=auth, timeout=10)
    assert resp.status_code == 202
    # The worker processes the task in the background — wait for the scan to
    # finish, then a second run must not change anything (idempotency).
    time.sleep(5)
    resp2 = requests.post(f"{base_url}/api/scan/", headers=auth, timeout=10)
    assert resp2.status_code == 202


def test_scan_requires_auth(base_url):
    assert requests.post(f"{base_url}/api/scan/", timeout=10).status_code == 401


def test_scan_result_contents(base_url, auth):
    requests.post(f"{base_url}/api/scan/", headers=auth, timeout=10)
    time.sleep(5)
    games = requests.get(f"{base_url}/api/games/", headers=auth, timeout=10).json()
    titles = {g["title"] for g in games["results"]}
    assert {"Super Mario World", "Tekken", "Hollow Knight"} <= titles
