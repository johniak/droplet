"""Okładki Switcha z titledb (blawar/titledb): dopasowanie po title id.

libretro-thumbnails nie ma repozytorium Switcha, a nazwy dumpów niosą title id,
więc zamiast zgadywać po tytule bierzemy ikonę eShopu dokładnie tej gry.
Plik `US.en.json` ma ~90 MB — trzymamy go w cache i czytamy strumieniowo
(ijson), wyciągając tylko potrzebne wpisy.
"""

import io
import time
from pathlib import Path

import ijson
import requests
from PIL import Image

from library.models import Game, GameFile
from library.scanner.switch import parse_switch

from .paths import _base

TITLEDB_URL = "https://raw.githubusercontent.com/blawar/titledb/master/US.en.json"
TITLEDB_TTL = 7 * 24 * 3600


def titledb_path() -> Path:
    return _base() / "index" / "titledb.US.en.json"


def ensure_titledb() -> Path:
    """Świeża kopia titledb na dysku; przy błędzie sieci zostaje stara, jeśli jest."""
    path = titledb_path()
    if path.exists() and time.time() - path.stat().st_mtime < TITLEDB_TTL:
        return path
    try:
        with requests.get(TITLEDB_URL, timeout=300, stream=True) as resp:
            resp.raise_for_status()
            path.parent.mkdir(parents=True, exist_ok=True)
            tmp = path.with_suffix(".part")
            with tmp.open("wb") as out:
                for chunk in resp.iter_content(1 << 20):
                    out.write(chunk)
            tmp.replace(path)
    except requests.RequestException:
        if path.exists():
            return path
        raise
    return path


def icon_urls(title_ids: set[str]) -> dict[str, str]:
    """title id → URL ikony (albo banera, gdy ikony brak) dla podanych gier."""
    wanted = {t.upper() for t in title_ids}
    found: dict[str, str] = {}
    if not wanted:
        return found
    with ensure_titledb().open("rb") as fh:
        for _, entry in ijson.kvitems(fh, ""):
            tid = (entry.get("id") or "").upper()
            if tid in wanted and tid not in found:
                url = entry.get("iconUrl") or entry.get("bannerUrl")
                if url:
                    found[tid] = url
                if len(found) == len(wanted):
                    break
    return found


def base_title_id(game: Game) -> str | None:
    """Title id z nazwy pliku bazowego (pierwszy plik `base` z tagiem)."""
    for gf in game.files.filter(role=GameFile.Role.BASE).order_by("relative_path"):
        info = parse_switch(Path(gf.relative_path).stem)
        if info.title_id:
            return info.title_id
    return None


def download_image(url: str, dest: Path) -> None:
    """Pobiera obraz (JPG/PNG) i zapisuje jako PNG — reszta pipeline’u zakłada PNG."""
    resp = requests.get(url, timeout=60)
    resp.raise_for_status()
    img = Image.open(io.BytesIO(resp.content)).convert("RGB")
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest, format="PNG")
