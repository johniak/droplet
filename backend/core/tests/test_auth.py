import pytest
from django.contrib.auth.models import User
from rest_framework.test import APIClient


@pytest.fixture
def user(db):
    return User.objects.create_user(username="jan", password="sekret123")


def test_token_for_valid_credentials(user):
    resp = APIClient().post(
        "/api/auth/token/", {"username": "jan", "password": "sekret123"}
    )
    assert resp.status_code == 200
    assert "token" in resp.json()


def test_bad_credentials_rejected(user):
    resp = APIClient().post("/api/auth/token/", {"username": "jan", "password": "zle"})
    assert resp.status_code == 400


def test_me_with_token(user):
    token = (
        APIClient()
        .post("/api/auth/token/", {"username": "jan", "password": "sekret123"})
        .json()["token"]
    )
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Token {token}")
    resp = client.get("/api/me/")
    assert resp.status_code == 200
    assert resp.json() == {"username": "jan"}


def test_me_without_token_is_401(db):
    assert APIClient().get("/api/me/").status_code == 401


def test_login_view_declares_throttle_scope():
    from core.views import ObtainTokenView

    assert ObtainTokenView.throttle_scope == "login"


def test_many_logins_not_throttled_in_tests(user):
    client = APIClient()
    for _ in range(15):
        resp = client.post(
            "/api/auth/token/", {"username": "jan", "password": "sekret123"}
        )
        assert resp.status_code == 200


def test_shared_auth_client_fixture(auth_client):
    assert auth_client.get("/api/me/").json() == {"username": "jan"}
