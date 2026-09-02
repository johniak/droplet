import json
import time

import pytest
import requests
import responses

from covers.paths import index_path
from covers.thumbnails import download_boxart, fetch_index

TREE = {
    "tree": [
        {"path": "Named_Boxarts/Super Mario World (USA).png", "type": "blob"},
        {"path": "Named_Boxarts/F-Zero (USA).png", "type": "blob"},
        {"path": "Named_Snaps/Super Mario World (USA).png", "type": "blob"},
        {"path": "README.md", "type": "blob"},
    ]
}

_TREE_URL = (
    "https://api.github.com/repos/libretro-thumbnails/Nintendo_-_SNES"
    "/git/trees/master"
)


@responses.activate
def test_fetch_index_filters_boxarts(settings, tmp_path):
    settings.DATA_DIR = tmp_path
    responses.get(_TREE_URL, json=TREE)
    names = fetch_index("Nintendo_-_SNES")
    assert names == ["F-Zero (USA)", "Super Mario World (USA)"]


@responses.activate
def test_fetch_index_uses_cache(settings, tmp_path):
    settings.DATA_DIR = tmp_path
    p = index_path("Nintendo_-_SNES")
    p.parent.mkdir(parents=True)
    p.write_text(json.dumps({"fetched_at": time.time(), "names": ["Cached (USA)"]}))
    names = fetch_index("Nintendo_-_SNES")
    assert names == ["Cached (USA)"]


@responses.activate
def test_fetch_index_falls_back_to_stale_cache_on_http_error(settings, tmp_path):
    settings.DATA_DIR = tmp_path
    p = index_path("Nintendo_-_SNES")
    p.parent.mkdir(parents=True)
    p.write_text(
        json.dumps(
            {"fetched_at": time.time() - 30 * 24 * 3600, "names": ["Stale (USA)"]}
        )
    )
    responses.get(_TREE_URL, status=503)
    assert fetch_index("Nintendo_-_SNES") == ["Stale (USA)"]


@responses.activate
def test_fetch_index_raises_without_cache(settings, tmp_path):
    settings.DATA_DIR = tmp_path
    responses.get(_TREE_URL, status=503)
    with pytest.raises(requests.RequestException):
        fetch_index("Nintendo_-_SNES")


@responses.activate
def test_download_boxart(settings, tmp_path):
    settings.DATA_DIR = tmp_path
    responses.get(
        "https://raw.githubusercontent.com/libretro-thumbnails/R"
        "/master/Named_Boxarts/Mario%20%28USA%29.png",
        body=b"PNGDATA",
    )
    dest = tmp_path / "out.png"
    download_boxart("R", "Mario (USA)", dest)
    assert dest.read_bytes() == b"PNGDATA"


@responses.activate
def test_download_boxart_follows_a_symlink(settings, tmp_path):
    # Regional duplicates in libretro-thumbnails are git symlinks: raw returns
    # the target's name, not a PNG.
    settings.DATA_DIR = tmp_path
    responses.get(
        "https://raw.githubusercontent.com/libretro-thumbnails/R"
        "/master/Named_Boxarts/Mario%20%28Australia%29.png",
        body=b"Mario (USA).png",
    )
    responses.get(
        "https://raw.githubusercontent.com/libretro-thumbnails/R"
        "/master/Named_Boxarts/Mario%20%28USA%29.png",
        body=b"\x89PNG\r\n\x1a\nREAL",
    )
    dest = tmp_path / "out.png"
    download_boxart("R", "Mario (Australia)", dest)
    assert dest.read_bytes() == b"\x89PNG\r\n\x1a\nREAL"


@responses.activate
def test_download_boxart_keeps_a_non_png_body_when_it_is_not_a_symlink(
    settings, tmp_path
):
    settings.DATA_DIR = tmp_path
    responses.get(
        "https://raw.githubusercontent.com/libretro-thumbnails/R"
        "/master/Named_Boxarts/Mario.png",
        body=b"nie-obrazek-ale-i-nie-symlink",
    )
    dest = tmp_path / "out.png"
    download_boxart("R", "Mario", dest)
    assert dest.read_bytes() == b"nie-obrazek-ale-i-nie-symlink"
