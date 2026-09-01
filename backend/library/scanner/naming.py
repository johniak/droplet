"""Title normalization used for grouping files into games and cover matching."""

import re
import unicodedata

_TAGS = re.compile(r"[\(\[][^\)\]]*[\)\]]")
_ARTICLE = re.compile(r"^(?P<t>.+), (?P<a>The|A|An|Le|La|Les|Der|Die|Das)$")


def display_title(stem: str) -> str:
    s = _TAGS.sub(" ", stem)
    s = re.sub(r"\s+", " ", s).strip(" -_.")
    m = _ARTICLE.match(s)
    if m:
        s = f"{m.group('a')} {m.group('t')}"
    return s


def normalize_title(stem: str) -> str:
    s = display_title(stem)
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-z0-9]+", " ", s.lower())
    return re.sub(r"\s+", " ", s).strip()
