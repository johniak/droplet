import pytest
from rest_framework.test import APIClient

from library.models import Game, System


@pytest.fixture
def data(db):
    snes = System.objects.create(
        code="snes", name="SNES", directory="snes", sort_order=2
    )
    psx = System.objects.create(
        code="psx", name="PlayStation", directory="psx", sort_order=1
    )
    System.objects.create(code="pusty", name="Pusty", directory="pusty")
    Game.objects.create(system=snes, title="Mario", normalized_title="mario")
    Game.objects.create(system=snes, title="Zelda", normalized_title="zelda")
    Game.objects.create(system=psx, title="Tekken", normalized_title="tekken")


def test_systems_sorted_with_counts(auth_client, data):
    resp = auth_client.get("/api/systems/")
    assert resp.status_code == 200
    body = resp.json()
    assert [s["code"] for s in body] == ["psx", "snes"]
    assert body[1]["game_count"] == 2


def test_systems_require_auth(db):
    assert APIClient().get("/api/systems/").status_code == 401
