import pytest
from rest_framework.test import APIClient

from covers.models import Cover
from covers.paths import full_path, thumb_path
from library.models import Game, System


@pytest.fixture
def game_with_cover(db, settings, tmp_path):
    settings.DATA_DIR = tmp_path
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    Cover.objects.create(game=g, source=Cover.Source.LIBRETRO, match_name="Mario")
    for p in (full_path(g.id), thumb_path(g.id)):
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(b"PNG" + p.parent.name.encode())
    return g


def test_cover_thumb_default(auth_client, game_with_cover):
    resp = auth_client.get(f"/api/games/{game_with_cover.id}/cover")
    assert resp.status_code == 200
    assert b"".join(resp.streaming_content) == b"PNGthumb"
    assert resp["Cache-Control"] == "private, max-age=86400"


def test_cover_full(auth_client, game_with_cover):
    resp = auth_client.get(f"/api/games/{game_with_cover.id}/cover?size=full")
    assert b"".join(resp.streaming_content) == b"PNGfull"


def test_cover_missing_404(auth_client, db):
    s = System.objects.create(code="x", name="X", directory="x")
    g = Game.objects.create(system=s, title="Bez", normalized_title="bez")
    assert auth_client.get(f"/api/games/{g.id}/cover").status_code == 404


def test_cover_record_without_file_404(auth_client, game_with_cover):
    thumb_path(game_with_cover.id).unlink()
    assert auth_client.get(f"/api/games/{game_with_cover.id}/cover").status_code == 404


def test_cover_requires_auth(game_with_cover):
    assert APIClient().get(f"/api/games/{game_with_cover.id}/cover").status_code == 401
