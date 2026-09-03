import pytest

from library.scanner.switch import parse_switch, title_prefix


@pytest.mark.parametrize(
    "stem,tid,role,version",
    [
        ("Hollow Knight [0100633007D48000][v0]", "0100633007D48000", "base", "v0"),
        (
            "Hollow Knight [UPD][0100633007D48800][v196608]",
            "0100633007D48800",
            "update",
            "v196608",
        ),
        (
            "Hollow Knight - Voidheart [DLC][0100633007D49001]",
            "0100633007D49001",
            "dlc",
            "",
        ),
        ("Celeste (UPD) (v1.2.6)", None, "update", "v1.2.6"),
        ("Celeste", None, "base", ""),
        # DLC rozpoznane po końcówce title id (13. cyfra podbita, końcówka != 000/800)
        (
            "The Witcher 3 Wild Hunt [PL Language Pack][0100E67012925004][US][v0]",
            "0100E67012925004",
            "dlc",
            "v0",
        ),
        # końcówka 800 bez tagu = update
        ("Hogwarts Legacy [0100F7E00C70E800][v327680][US]", "0100F7E00C70E800", "update", "v327680"),
        # tag UPD ma pierwszeństwo nad końcówką
        ("Weird [UPD][0100E67012925004]", "0100E67012925004", "update", ""),
        # tag DLC ma pierwszeństwo nad końcówką 000
        ("Weird [DLC][0100E67012924000]", "0100E67012924000", "dlc", ""),
        # nawiasy okrągłe też działają
        ("Pokemon Shield (RF) (01008DB008C2C000)(v0)", "01008DB008C2C000", "base", "v0"),
    ],
)
def test_parse_switch(stem, tid, role, version):
    info = parse_switch(stem)
    assert (info.title_id, info.role, info.version) == (tid, role, version)


def test_title_prefix_groups_family():
    assert title_prefix("0100633007D48000") == title_prefix("0100633007D48800")
