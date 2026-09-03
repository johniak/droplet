import io
import json
import os
import time

import pytest
import requests
import responses
from PIL import Image

from covers import titledb
from covers.models import Cover
from covers.paths import full_path, thumb_path
from covers.service import match_all
from covers.titledb import base_title_id, download_image, ensure_titledb, icon_urls
from library.models import Game, GameFile, System

TID = "0100633007D48000"
ICON = "https://img-eshop.example/hk-icon.jpg"
BANNER = "https://img-eshop.example/other-banner.jpg"


def _jpg_bytes(w=64, h=64):
    buf = io.BytesIO()
    Image.new("RGB", (w, h), "blue").save(buf, format="JPEG")
    return buf.getvalue()


def _db():
    return json.dumps(
        {
            "70010000000001": {"id": "0100000000000001", "iconUrl": "x"},
            "70010000003208": {"id": TID.lower(), "iconUrl": ICON, "bannerUrl": "b"},
            "70010000000002": {"id": "0100633007D49000", "bannerUrl": BANNER},
            "70010000000003": {"id": "0100633007D4A000"},
            "70010000000004": {"name": "no id"},
        }
    )


@pytest.fixture
def data_dir(settings, tmp_path):
    settings.DATA_DIR = tmp_path
    return tmp_path


@pytest.fixture
def switch_game(db):
    s = System.objects.create(code="switch", name="Switch", directory="switch")
    g = Game.objects.create(
        system=s, title="Hollow Knight", normalized_title="hollow knight",
        folder="switch/Hollow Knight",
    )
    GameFile.objects.create(
        game=g, relative_path=f"switch/Hollow Knight/Hollow Knight [{TID}][v0].nsp",
        role="base", size=1, mtime_ns=0,
    )
    GameFile.objects.create(
        game=g, relative_path=f"switch/Hollow Knight/Hollow Knight [UPD][0100633007D48800][v1].nsp",
        role="update", size=1, mtime_ns=0,
    )
    return g


@responses.activate
def test_ensure_titledb_downloads_when_missing(data_dir):
    responses.get(titledb.TITLEDB_URL, body=_db())
    path = ensure_titledb()
    assert path.read_text() == _db()
    assert not path.with_suffix(".part").exists()


@responses.activate
def test_ensure_titledb_uses_fresh_cache_without_network(data_dir):
    path = titledb.titledb_path()
    path.parent.mkdir(parents=True)
    path.write_text("{}")
    assert ensure_titledb() == path  # brak zarejestrowanych odpowiedzi = brak sieci


@responses.activate
def test_ensure_titledb_refreshes_stale_cache(data_dir):
    path = titledb.titledb_path()
    path.parent.mkdir(parents=True)
    path.write_text("{}")
    old = time.time() - titledb.TITLEDB_TTL - 10
    os.utime(path, (old, old))
    responses.get(titledb.TITLEDB_URL, body=_db())
    assert ensure_titledb().read_text() == _db()


@responses.activate
def test_ensure_titledb_keeps_stale_copy_on_network_error(data_dir):
    path = titledb.titledb_path()
    path.parent.mkdir(parents=True)
    path.write_text("{}")
    old = time.time() - titledb.TITLEDB_TTL - 10
    os.utime(path, (old, old))
    responses.get(titledb.TITLEDB_URL, body=requests.ConnectionError("down"))
    assert ensure_titledb().read_text() == "{}"


@responses.activate
def test_ensure_titledb_raises_without_any_copy(data_dir):
    responses.get(titledb.TITLEDB_URL, status=500)
    with pytest.raises(requests.HTTPError):
        ensure_titledb()


@responses.activate
def test_icon_urls_streams_and_falls_back_to_banner(data_dir):
    responses.get(titledb.TITLEDB_URL, body=_db())
    urls = icon_urls({TID, "0100633007d49000", "0100633007D4A000", "0100000000000099"})
    assert urls == {TID: ICON, "0100633007D49000": BANNER}


def test_icon_urls_empty_set_needs_no_file(data_dir):
    assert icon_urls(set()) == {}


@responses.activate
def test_icon_urls_stops_early_when_everything_found(data_dir, monkeypatch):
    responses.get(titledb.TITLEDB_URL, body=_db())
    seen = []
    real = titledb.ijson.kvitems

    def spy(fh, prefix):
        for item in real(fh, prefix):
            seen.append(item[0])
            yield item

    monkeypatch.setattr(titledb.ijson, "kvitems", spy)
    assert icon_urls({"0100000000000001"}) == {"0100000000000001": "x"}
    assert seen == ["70010000000001"]


@pytest.mark.django_db
def test_base_title_id(switch_game):
    assert base_title_id(switch_game) == TID
    GameFile.objects.filter(role="base").update(relative_path="switch/HK/no tags.nsp")
    assert base_title_id(switch_game) is None
    GameFile.objects.all().delete()
    assert base_title_id(switch_game) is None


@responses.activate
def test_download_image_converts_jpg_to_png(data_dir, tmp_path):
    responses.get(ICON, body=_jpg_bytes())
    dest = tmp_path / "out" / "1.png"
    download_image(ICON, dest)
    assert dest.read_bytes().startswith(b"\x89PNG")


@responses.activate
@pytest.mark.django_db
def test_match_all_switch_by_title_id(data_dir, switch_game):
    responses.get(titledb.TITLEDB_URL, body=_db())
    responses.get(ICON, body=_jpg_bytes())
    stats = match_all()
    assert stats == {"matched": 1, "skipped": 0, "errors": []}
    cover = Cover.objects.get(game=switch_game)
    assert (cover.source, cover.match_name, cover.score, cover.is_manual) == (
        "titledb", TID, 100.0, False,
    )
    assert full_path(switch_game.id).exists() and thumb_path(switch_game.id).exists()
    # drugi przebieg: gra ma już okładkę, nic do roboty
    assert match_all() == {"matched": 0, "skipped": 0, "errors": []}


@responses.activate
@pytest.mark.django_db
def test_match_all_switch_skips_games_without_tid_or_entry(data_dir, switch_game):
    s = switch_game.system
    no_tid = Game.objects.create(system=s, title="Homebrew", normalized_title="homebrew", folder="switch/Homebrew")
    GameFile.objects.create(game=no_tid, relative_path="switch/Homebrew/hb.nro", role="base", size=1, mtime_ns=0)
    unknown = Game.objects.create(system=s, title="Unknown", normalized_title="unknown", folder="switch/Unknown")
    GameFile.objects.create(
        game=unknown, relative_path="switch/Unknown/U [0100FFFFFFFF0000][v0].nsp", role="base", size=1, mtime_ns=0,
    )
    responses.get(titledb.TITLEDB_URL, body=_db())
    responses.get(ICON, body=_jpg_bytes())
    stats = match_all()
    assert stats == {"matched": 1, "skipped": 2, "errors": []}


@responses.activate
@pytest.mark.django_db
def test_match_all_switch_records_titledb_error(data_dir, switch_game):
    responses.get(titledb.TITLEDB_URL, status=500)
    stats = match_all()
    assert stats["matched"] == 0 and stats["errors"] == [
        f"switch: titledb: 500 Server Error: Internal Server Error for url: {titledb.TITLEDB_URL}"
    ]


@responses.activate
@pytest.mark.django_db
def test_match_all_switch_records_download_error(data_dir, switch_game):
    responses.get(titledb.TITLEDB_URL, body=_db())
    responses.get(ICON, status=404)
    stats = match_all()
    assert stats["matched"] == 0 and len(stats["errors"]) == 1
    assert stats["errors"][0].startswith("Hollow Knight: 404")
    assert not Cover.objects.filter(game=switch_game).exists()


@responses.activate
@pytest.mark.django_db
def test_match_all_switch_without_games_touches_no_network(data_dir):
    System.objects.create(code="switch", name="Switch", directory="switch")
    assert match_all() == {"matched": 0, "skipped": 0, "errors": []}
