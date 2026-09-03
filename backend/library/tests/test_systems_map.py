from library.scanner.systems_map import lookup_system


def test_full_retroarch_name():
    spec = lookup_system("Nintendo - Super Nintendo Entertainment System")
    assert spec.code == "snes"
    assert spec.thumbnail_repo == "Nintendo_-_Super_Nintendo_Entertainment_System"


def test_short_alias_case_insensitive():
    assert lookup_system("SNES").code == "snes"
    assert lookup_system("psx").code == "psx"


def test_switch_flag():
    assert lookup_system("switch").is_switch is True
    assert lookup_system("snes").is_switch is False


def test_unknown_returns_none():
    assert lookup_system("Losowy Katalog") is None


def test_switch_has_no_thumbnail_repo():
    # libretro-thumbnails has no Switch repository (the API returns 404), so the
    # automatic matcher must skip the system instead of erroring on every scan.
    assert lookup_system("switch").thumbnail_repo == ""


def test_bios_pseudo_system():
    for name in ("bios", "BIOS", "firmware", "system"):
        spec = lookup_system(name)
        assert spec.code == "bios" and spec.is_switch is False
    assert lookup_system("bios").thumbnail_repo == ""
