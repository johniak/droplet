"""Parsers for the playlist formats that group disc images into one game."""

import re

_FILE = re.compile(r'^\s*FILE\s+"([^"]+)"', re.MULTILINE)


def parse_cue(text: str) -> list[str]:
    return _FILE.findall(text)


def parse_m3u(text: str) -> list[str]:
    return [
        line.strip()
        for line in text.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
