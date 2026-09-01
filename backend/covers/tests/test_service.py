import io

import pytest
import responses
from PIL import Image

from covers.models import Cover
from covers.paths import full_path, thumb_path
from covers.service import match_all, match_game
from library.models import Game, System

_BOXART_URL = (
    "https://raw.githubusercontent.com/libretro-thumbnails/R"
    "/master/Named_Boxarts/Super%20Mario%20World%20%28USA%29.png"
)
_INDEX_URL = "https://api.github.com/repos/libretro-thumbnails/R/git/trees/master"


def _png_bytes(w=600, h=800):
    buf = io.BytesIO()
    Image.new("RGB", (w, h), "red").save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture
def snes_game(db):
    s = System.objects.create(
        code="snes", name="SNES", directory="snes", thumbnail_repo="R"
    )
    return Game.objects.create(
        system=s, title="Super Mario World", normalized_title="super mario world"
    )


@responses.activate
@pytest.mark.django_db
def test_match_game_downloads_and_thumbs(settings, tmp_path, snes_game):
    settings.DATA_DIR = tmp_path
    responses.get(_BOXART_URL, body=_png_bytes())
    ok = match_game(snes_game, ["Super Mario World (USA)"])
    assert ok
    cover = Cover.objects.get(game=snes_game)
    assert cover.score == 100 and cover.source == Cover.Source.LIBRETRO
    assert full_path(snes_game.id).exists()
    assert Image.open(thumb_path(snes_game.id)).width == 256


@pytest.mark.django_db
def test_match_game_skips_manual(settings, tmp_path, snes_game):
    settings.DATA_DIR = tmp_path
    Cover.objects.create(
        game=snes_game, source=Cover.Source.MANUAL, is_manual=True, match_name="X"
    )
    assert match_game(snes_game, ["Super Mario World (USA)"]) is False
    assert snes_game.cover.match_name == "X"


@pytest.mark.django_db
def test_match_game_below_threshold_no_cover(settings, tmp_path, snes_game):
    settings.DATA_DIR = tmp_path
    assert match_game(snes_game, ["Totally Different Game (USA)"]) is False
    assert not Cover.objects.filter(game=snes_game).exists()


@responses.activate
@pytest.mark.django_db
def test_match_all_counts(settings, tmp_path, snes_game):
    settings.DATA_DIR = tmp_path
    responses.get(
        _INDEX_URL,
        json={
            "tree": [
                {"path": "Named_Boxarts/Super Mario World (USA).png", "type": "blob"}
            ]
        },
    )
    responses.get(_BOXART_URL, body=_png_bytes())
    Game.objects.create(
        system=snes_game.system, title="Nieznana Gra", normalized_title="nieznana gra"
    )
    stats = match_all()
    assert stats["matched"] == 1
    assert stats["skipped"] == 1


@responses.activate
@pytest.mark.django_db
def test_match_all_records_index_error(settings, tmp_path, snes_game):
    settings.DATA_DIR = tmp_path
    responses.get(_INDEX_URL, status=500)
    stats = match_all()
    assert stats["matched"] == 0
    assert stats["errors"] and stats["errors"][0].startswith("snes: index:")


@pytest.mark.django_db
def test_match_all_records_per_game_error(settings, tmp_path, snes_game, monkeypatch):
    settings.DATA_DIR = tmp_path
    monkeypatch.setattr(
        "covers.service.fetch_index", lambda repo: ["Super Mario World (USA)"]
    )

    def boom(*args, **kwargs):
        raise OSError("dysk pełny")

    monkeypatch.setattr("covers.service.download_boxart", boom)
    stats = match_all()
    assert stats["errors"] == ["Super Mario World: dysk pełny"]


@pytest.mark.django_db
def test_scan_task_triggers_cover_matching(settings, tmp_path, monkeypatch):
    from library.tasks import scan_library

    calls = []
    monkeypatch.setattr("covers.tasks.match_all", lambda: calls.append(1) or {})
    settings.LIBRARY_ROOT = tmp_path
    settings.COVERS_AUTO_MATCH = True
    scan_library.enqueue()
    assert calls == [1]


@pytest.mark.django_db
def test_scan_task_respects_auto_covers_flag(settings, tmp_path, monkeypatch):
    from library.tasks import scan_library

    calls = []
    monkeypatch.setattr("covers.tasks.match_all", lambda: calls.append(1) or {})
    settings.LIBRARY_ROOT = tmp_path
    settings.COVERS_AUTO_MATCH = False
    scan_library.enqueue()
    assert calls == []
