"""Client for the libretro-thumbnails GitHub repositories (no API key needed)."""

import json
import time
from pathlib import Path
from urllib.parse import quote

import requests

from .paths import ensure_dirs, index_path

INDEX_TTL = 7 * 24 * 3600
_API = (
    "https://api.github.com/repos/libretro-thumbnails/{repo}"
    "/git/trees/master?recursive=1"
)
_RAW = (
    "https://raw.githubusercontent.com/libretro-thumbnails/{repo}"
    "/master/Named_Boxarts/{name}.png"
)


def fetch_index(repo: str) -> list[str]:
    ensure_dirs()
    cache = index_path(repo)
    cached = None
    if cache.exists():
        cached = json.loads(cache.read_text())
        if time.time() - cached["fetched_at"] < INDEX_TTL:
            return cached["names"]
    try:
        resp = requests.get(_API.format(repo=repo), timeout=30)
        resp.raise_for_status()
    except requests.RequestException:
        if cached is not None:
            return cached["names"]
        raise
    names = sorted(
        Path(item["path"]).stem
        for item in resp.json()["tree"]
        if item["type"] == "blob"
        and item["path"].startswith("Named_Boxarts/")
        and item["path"].endswith(".png")
    )
    cache.write_text(json.dumps({"fetched_at": time.time(), "names": names}))
    return names


def download_boxart(repo: str, name: str, dest: Path) -> None:
    url = _RAW.format(repo=repo, name=quote(name))
    resp = requests.get(url, timeout=60)
    resp.raise_for_status()
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(resp.content)
