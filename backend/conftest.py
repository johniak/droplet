import pytest
from django.contrib.auth.models import User
from rest_framework.test import APIClient


@pytest.fixture
def auth_client(db):
    User.objects.create_user(username="jan", password="s3")
    client = APIClient()
    token = client.post("/api/auth/token/", {"username": "jan", "password": "s3"}).json()[
        "token"
    ]
    client.credentials(HTTP_AUTHORIZATION=f"Token {token}")
    return client


@pytest.fixture(autouse=True)
def _no_network(monkeypatch):
    """No test reaches the network; `responses.activate` overrides this block
    only inside the test it decorates."""

    def _blocked(self, request, *args, **kwargs):
        raise RuntimeError(f"Sieć zablokowana w testach: {request.url}")

    monkeypatch.setattr("requests.adapters.HTTPAdapter.send", _blocked)
