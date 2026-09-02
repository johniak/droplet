import pytest

from library.models import Game, GameFile, System


@pytest.fixture
def switch_game(db):
    sw = System.objects.create(code="switch", name="Switch", directory="switch")
    g = Game.objects.create(
        system=sw,
        folder="switch/Hollow Knight",
        title="Hollow Knight",
        normalized_title="hollow knight",
    )
    GameFile.objects.create(
        game=g,
        relative_path="switch/Hollow Knight/dlc/hk-dlc.nsp",
        role="dlc",
        size=3,
        mtime_ns=1,
    )
    GameFile.objects.create(
        game=g, relative_path="switch/Hollow Knight/hk.nsp", role="base", size=1, mtime_ns=1
    )
    GameFile.objects.create(
        game=g,
        relative_path="switch/Hollow Knight/hk-upd.nsp",
        role="update",
        version="v196608",
        size=2,
        mtime_ns=1,
    )
    return g


def test_detail_manifest_sorted(auth_client, switch_game):
    body = auth_client.get(f"/api/games/{switch_game.id}/").json()
    assert body["system_name"] == "Switch"
    assert body["folder"] == "Hollow Knight"
    assert [f["role"] for f in body["files"]] == ["base", "update", "dlc"]
    assert body["files"][0]["name"] == "hk.nsp"
    assert body["files"][1]["version"] == "v196608"
    assert body["files"][2]["name"] == "dlc/hk-dlc.nsp"


def test_detail_404(auth_client):
    assert auth_client.get("/api/games/99999/").status_code == 404


def test_detail_with_empty_folder_uses_basename(auth_client, db):
    sw = System.objects.create(code="switch", name="Switch", directory="switch")
    g = Game.objects.create(system=sw, title="Legacy", normalized_title="legacy")
    GameFile.objects.create(
        game=g, relative_path="switch/legacy.nsp", role="base", size=1, mtime_ns=1
    )
    body = auth_client.get(f"/api/games/{g.id}/").json()
    assert body["folder"] == ""
    assert body["files"][0]["name"] == "legacy.nsp"
