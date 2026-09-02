import pytest

from library.models import Game, GameFile, System


@pytest.fixture
def two_games(db):
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    psx = System.objects.create(code="psx", name="PSX", directory="psx")
    m = Game.objects.create(system=snes, folder="snes/Mario (USA)", title="Mario",
                            normalized_title="mario")
    GameFile.objects.create(game=m, relative_path="snes/Mario (USA)/Mario (USA).sfc",
                            size=10, mtime_ns=1)
    ff = Game.objects.create(system=psx, folder="psx/FF7", title="FF7", normalized_title="ff7")
    GameFile.objects.create(game=ff, relative_path="psx/FF7/disc1/FF7 (Disc 1).cue",
                            role="disc", disc_number=1, size=1, mtime_ns=1)
    GameFile.objects.create(game=ff, relative_path="psx/FF7/FF7.m3u", role="support",
                            size=2, mtime_ns=1)
    return m, ff


def test_manifest_lists_all_games_with_files(auth_client, two_games):
    body = auth_client.get("/api/manifest/").json()
    assert [e["id"] for e in body] == sorted(e["id"] for e in body)
    mario = next(e for e in body if e["folder"] == "Mario (USA)")
    assert mario["system_code"] == "snes"
    assert mario["files"] == [
        {"id": mario["files"][0]["id"], "name": "Mario (USA).sfc", "role": "base",
         "version": "", "disc_number": None, "size": 10}
    ]
    ff = next(e for e in body if e["folder"] == "FF7")
    assert [f["name"] for f in ff["files"]] == ["disc1/FF7 (Disc 1).cue", "FF7.m3u"]


def test_manifest_requires_auth(client, two_games):
    assert client.get("/api/manifest/").status_code == 401


def test_manifest_is_empty_without_games(auth_client):
    assert auth_client.get("/api/manifest/").json() == []
