from covers.matching import best_match, top_candidates

CANDIDATES = [
    "Super Mario World (USA)",
    "Super Mario World 2 - Yoshi's Island (USA)",
    "F-Zero (USA)",
    "Legend of Zelda, The - A Link to the Past (USA)",
]


def test_exact_normalized_match_wins():
    m = best_match("super mario world", CANDIDATES)
    assert m.name == "Super Mario World (USA)"
    assert m.score == 100


def test_fuzzy_match_above_threshold():
    m = best_match("zelda a link to the past", CANDIDATES)
    assert m.name == "Legend of Zelda, The - A Link to the Past (USA)"
    assert m.score >= 85


def test_below_threshold_returns_none():
    assert best_match("wario land 4", CANDIDATES) is None


def test_top_candidates_sorted():
    tops = top_candidates("mario world", CANDIDATES, n=2)
    assert len(tops) == 2
    assert tops[0].score >= tops[1].score


def test_empty_candidate_list_returns_none():
    assert best_match("super mario world", []) is None
