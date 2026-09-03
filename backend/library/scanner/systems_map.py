"""Mapping of first-level library directory names to known systems."""

from dataclasses import dataclass


@dataclass(frozen=True)
class SystemSpec:
    code: str
    name: str
    thumbnail_repo: str
    is_switch: bool = False


_SPECS = [
    # Pliki systemowe (BIOS, firmware, klucze): zwykły system, każdy podkatalog
    # to paczka do pobrania; aplikacja chowa go z półek i pokazuje w Ustawieniach.
    SystemSpec("bios", "BIOS & firmware", ""),
    SystemSpec(
        "nes",
        "Nintendo Entertainment System",
        "Nintendo_-_Nintendo_Entertainment_System",
    ),
    SystemSpec(
        "snes", "Super Nintendo", "Nintendo_-_Super_Nintendo_Entertainment_System"
    ),
    SystemSpec("n64", "Nintendo 64", "Nintendo_-_Nintendo_64"),
    SystemSpec("gc", "GameCube", "Nintendo_-_GameCube"),
    SystemSpec("gb", "Game Boy", "Nintendo_-_Game_Boy"),
    SystemSpec("gbc", "Game Boy Color", "Nintendo_-_Game_Boy_Color"),
    SystemSpec("gba", "Game Boy Advance", "Nintendo_-_Game_Boy_Advance"),
    SystemSpec("nds", "Nintendo DS", "Nintendo_-_Nintendo_DS"),
    SystemSpec("n3ds", "Nintendo 3DS", "Nintendo_-_Nintendo_3DS"),
    # libretro-thumbnails has no Switch repository, so there is nothing to
    # fetch — Switch covers are uploaded by hand in the admin.
    SystemSpec("switch", "Nintendo Switch", "", is_switch=True),
    SystemSpec("psx", "PlayStation", "Sony_-_PlayStation"),
    SystemSpec("ps2", "PlayStation 2", "Sony_-_PlayStation_2"),
    SystemSpec("psp", "PlayStation Portable", "Sony_-_PlayStation_Portable"),
    SystemSpec("megadrive", "Mega Drive / Genesis", "Sega_-_Mega_Drive_-_Genesis"),
    SystemSpec("saturn", "Sega Saturn", "Sega_-_Saturn"),
    SystemSpec("dreamcast", "Dreamcast", "Sega_-_Dreamcast"),
]

_ALIASES = {
    "bios": ["bios", "firmware", "system"],
    "nes": ["nes", "nintendo - nintendo entertainment system", "famicom"],
    "snes": ["snes", "nintendo - super nintendo entertainment system", "sfc"],
    "n64": ["n64", "nintendo - nintendo 64"],
    "gc": ["gc", "gamecube", "nintendo - gamecube", "ngc"],
    "gb": ["gb", "nintendo - game boy"],
    "gbc": ["gbc", "nintendo - game boy color"],
    "gba": ["gba", "nintendo - game boy advance"],
    "nds": ["nds", "nintendo - nintendo ds"],
    "n3ds": ["n3ds", "3ds", "nintendo - nintendo 3ds"],
    "switch": ["switch", "nintendo - nintendo switch", "nsw"],
    "psx": ["psx", "ps1", "sony - playstation"],
    "ps2": ["ps2", "sony - playstation 2"],
    "psp": ["psp", "sony - playstation portable"],
    "megadrive": ["megadrive", "genesis", "md", "sega - mega drive - genesis"],
    "saturn": ["saturn", "sega - saturn"],
    "dreamcast": ["dreamcast", "dc", "sega - dreamcast"],
}

_BY_ALIAS = {alias: spec for spec in _SPECS for alias in _ALIASES[spec.code]}


def lookup_system(directory_name: str) -> SystemSpec | None:
    return _BY_ALIAS.get(directory_name.strip().lower())
