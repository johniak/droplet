import pytest

from library.scanner.naming import display_title, normalize_title


@pytest.mark.parametrize(
    "stem,expected",
    [
        ("Super Mario World (USA)", "Super Mario World"),
        ("Legend of Zelda, The (USA) (Rev A) [!]", "The Legend of Zelda"),
        ("Final Fantasy VII (Europe) (Disc 1)", "Final Fantasy VII"),
        ("  Metroid   Prime  ", "Metroid Prime"),
    ],
)
def test_display_title(stem, expected):
    assert display_title(stem) == expected


@pytest.mark.parametrize(
    "stem,expected",
    [
        ("Super Mario World (USA)", "super mario world"),
        ("R-Type III (USA)", "r type iii"),
        ("Pokémon - Édition Rouge (France)", "pokemon edition rouge"),
    ],
)
def test_normalize_title(stem, expected):
    assert normalize_title(stem) == expected
