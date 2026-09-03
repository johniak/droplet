import time

import requests


def _scan_and_wait(base_url, auth):
    requests.post(f"{base_url}/api/scan/", headers=auth, timeout=10)
    for _ in range(30):
        games = requests.get(f"{base_url}/api/games/", headers=auth, timeout=10).json()
        if games["count"] >= 3:
            return games
        time.sleep(1)
    raise AssertionError("scan nie zaindeksował fixture-library")


def test_full_flow(base_url, auth):
    games = _scan_and_wait(base_url, auth)
    assert games["count"] == 4  # 3 gry + paczka bios/RetroArch

    systems = requests.get(f"{base_url}/api/systems/", headers=auth, timeout=10).json()
    assert {s["code"] for s in systems} >= {"snes", "psx", "switch", "bios"}

    mario = requests.get(
        f"{base_url}/api/games/",
        headers=auth,
        timeout=10,
        params={"search": "mario"},
    ).json()["results"][0]
    detail = requests.get(
        f"{base_url}/api/games/{mario['id']}/", headers=auth, timeout=10
    ).json()
    assert detail["folder"] == "Super Mario World (USA)"

    hollow = requests.get(
        f"{base_url}/api/games/",
        headers=auth,
        timeout=10,
        params={"search": "hollow"},
    ).json()["results"][0]
    detail = requests.get(
        f"{base_url}/api/games/{hollow['id']}/", headers=auth, timeout=10
    ).json()
    assert [f["role"] for f in detail["files"]] == ["base", "update", "mod"]

    tekken = requests.get(
        f"{base_url}/api/games/",
        headers=auth,
        timeout=10,
        params={"search": "tekken"},
    ).json()["results"][0]
    tekken_detail = requests.get(
        f"{base_url}/api/games/{tekken['id']}/", headers=auth, timeout=10
    ).json()
    assert {f["role"] for f in tekken_detail["files"]} == {"base", "support"}


def test_download_with_range_resume(base_url, auth):
    games = _scan_and_wait(base_url, auth)
    mario = next(g for g in games["results"] if "Mario" in g["title"])
    file_id = requests.get(
        f"{base_url}/api/games/{mario['id']}/", headers=auth, timeout=10
    ).json()["files"][0]["id"]
    url = f"{base_url}/api/files/{file_id}/download"

    full = requests.get(url, headers=auth, timeout=10)
    assert full.status_code == 200
    assert full.headers["Accept-Ranges"] == "bytes"

    part1 = requests.get(url, headers={**auth, "Range": "bytes=0-1"}, timeout=10)
    part2 = requests.get(url, headers={**auth, "Range": "bytes=2-"}, timeout=10)
    assert part1.status_code == 206 and part2.status_code == 206
    assert part1.content + part2.content == full.content

    bad = requests.get(url, headers={**auth, "Range": "bytes=999999-"}, timeout=10)
    assert bad.status_code == 416


def test_download_requires_auth(base_url, auth):
    games = _scan_and_wait(base_url, auth)
    mario = next(g for g in games["results"] if "Mario" in g["title"])
    file_id = requests.get(
        f"{base_url}/api/games/{mario['id']}/", headers=auth, timeout=10
    ).json()["files"][0]["id"]
    resp = requests.get(f"{base_url}/api/files/{file_id}/download", timeout=10)
    assert resp.status_code == 401
