"""On-disk locations of the cover cache under DATA_DIR."""

from pathlib import Path

from django.conf import settings


def _base() -> Path:
    return settings.DATA_DIR / "covers"


def full_path(game_id: int) -> Path:
    return _base() / "full" / f"{game_id}.png"


def thumb_path(game_id: int) -> Path:
    return _base() / "thumb" / f"{game_id}.png"


def index_path(repo: str) -> Path:
    return _base() / "index" / f"{repo}.json"


def ensure_dirs() -> None:
    for sub in ("full", "thumb", "index"):
        (_base() / sub).mkdir(parents=True, exist_ok=True)
