import os

import pytest
import requests


@pytest.fixture(autouse=True)
def _no_network():
    """Override the unit-suite network block: e2e talks to a real deployment."""
    yield


@pytest.fixture(scope="session")
def base_url() -> str:
    return os.environ.get("E2E_BASE_URL", "http://localhost:8800")


@pytest.fixture(scope="session")
def token(base_url) -> str:
    resp = requests.post(
        f"{base_url}/api/auth/token/",
        data={"username": "e2e", "password": "e2e-pass-123"},
        timeout=10,
    )
    resp.raise_for_status()
    return resp.json()["token"]


@pytest.fixture(scope="session")
def auth(token) -> dict:
    return {"Authorization": f"Token {token}"}
