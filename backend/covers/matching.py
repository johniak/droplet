"""Matching a game title against the boxart names of a thumbnails repo."""

from dataclasses import dataclass

from rapidfuzz import fuzz

from library.scanner.naming import normalize_title

THRESHOLD = 85


@dataclass(frozen=True)
class MatchResult:
    name: str
    score: float


def _scored(normalized_title: str, candidates: list[str]) -> list[MatchResult]:
    results = []
    for cand in candidates:
        norm = normalize_title(cand)
        score = (
            100.0
            if norm == normalized_title
            else fuzz.WRatio(normalized_title, norm)
        )
        results.append(MatchResult(name=cand, score=score))
    return sorted(results, key=lambda r: r.score, reverse=True)


def top_candidates(
    normalized_title: str, candidates: list[str], n: int = 5
) -> list[MatchResult]:
    return _scored(normalized_title, candidates)[:n]


def best_match(normalized_title: str, candidates: list[str]) -> MatchResult | None:
    if not candidates:
        return None
    best = _scored(normalized_title, candidates)[0]
    return best if best.score >= THRESHOLD else None
