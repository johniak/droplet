import requests


def test_health_open(base_url):
    resp = requests.get(f"{base_url}/api/health/", timeout=10)
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_me_requires_token(base_url):
    assert requests.get(f"{base_url}/api/me/", timeout=10).status_code == 401


def test_me_with_token(base_url, auth):
    resp = requests.get(f"{base_url}/api/me/", headers=auth, timeout=10)
    assert resp.status_code == 200
    assert resp.json()["username"] == "e2e"


def test_bad_login_rejected(base_url):
    resp = requests.post(
        f"{base_url}/api/auth/token/",
        data={"username": "e2e", "password": "zle"},
        timeout=10,
    )
    assert resp.status_code == 400
