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
    ],
)
def test_parse_switch(stem, tid, role, version):
    info = parse_switch(stem)
    assert (info.title_id, info.role, info.version) == (tid, role, version)


def test_title_prefix_groups_family():
    assert title_prefix("0100633007D48000") == title_prefix("0100633007D48800")
