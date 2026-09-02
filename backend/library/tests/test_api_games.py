import pytest
from rest_framework.test import APIClient

from covers.models import Cover
from library.models import Game, GameFile, System


@pytest.fixture
def data(db):
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    psx = System.objects.create(code="psx", name="PSX", directory="psx")
    mario = Game.objects.create(
        system=snes, title="Super Mario World", normalized_title="super mario world"
    )
    Game.objects.create(system=snes, title="Zelda", normalized_title="zelda")
    tekken = Game.objects.create(system=psx, title="Tekken", normalized_title="tekken")
    GameFile.objects.create(
        game=mario, relative_path="snes/m.sfc", size=100, mtime_ns=1
    )
    GameFile.objects.create(game=tekken, relative_path="psx/t.cue", size=10, mtime_ns=1)
    GameFile.objects.create(
        game=tekken, relative_path="psx/t.bin", size=990, mtime_ns=1, role="support"
    )
    Cover.objects.create(game=mario, source=Cover.Source.LIBRETRO, match_name="m")
    return {"mario": mario, "tekken": tekken}


def test_list_shape_and_order(auth_client, data):
    body = auth_client.get("/api/games/").json()
    assert body["count"] == 3
    titles = [g["title"] for g in body["results"]]
    assert titles == ["Super Mario World", "Tekken", "Zelda"]
    mario = body["results"][0]
    assert mario["system_code"] == "snes"
    assert mario["has_cover"] is True
    assert mario["total_size"] == 100


def test_filter_by_system(auth_client, data):
    body = auth_client.get("/api/games/?system=psx").json()
    assert [g["title"] for g in body["results"]] == ["Tekken"]
    assert body["results"][0]["total_size"] == 1000


def test_search(auth_client, data):
    body = auth_client.get("/api/games/?search=mario").json()
    assert body["count"] == 1


def test_games_require_auth(db):
    assert APIClient().get("/api/games/").status_code == 401


def test_list_includes_folder_without_system_prefix(auth_client, db):
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    Game.objects.create(
        system=snes, folder="snes/Mario (USA)", title="Mario (USA)",
        normalized_title="mario (usa)",
    )
    body = auth_client.get("/api/games/").json()
    assert body["results"][0]["folder"] == "Mario (USA)"
