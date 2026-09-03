"""Parsing of Switch dump filename tags: title id, role and version."""

import re
from dataclasses import dataclass

_TID = re.compile(r"[\[\(]([0-9A-Fa-f]{16})[\]\)]")
_VER = re.compile(r"[\[\(](v[\d.]+)[\]\)]", re.IGNORECASE)
_UPD = re.compile(r"[\[\(](UPD|UPDATE)[\]\)]", re.IGNORECASE)
_DLC = re.compile(r"[\[\(]DLC[\]\)]", re.IGNORECASE)


@dataclass(frozen=True)
class SwitchInfo:
    title_id: str | None
    role: str
    version: str


def title_prefix(title_id: str) -> str:
    """First 12 hex digits — shared by a base game, its updates and its DLC."""
    return title_id.upper()[:12]


def parse_switch(stem: str) -> SwitchInfo:
    tid_m = _TID.search(stem)
    tid = tid_m.group(1).upper() if tid_m else None
    ver_m = _VER.search(stem)
    version = ver_m.group(1) if ver_m else ""
    suffix = tid[-3:] if tid else None
    if _DLC.search(stem):
        role = "dlc"
    elif _UPD.search(stem) or suffix == "800":
        role = "update"
    elif suffix is not None and suffix != "000":
        # Title id spoza rodziny base/update: 13. cyfra podbita o 1 i licznik
        # w końcówce (…5001, …5002) — tak Nintendo numeruje DLC.
        role = "dlc"
    else:
        role = "base"
    return SwitchInfo(title_id=tid, role=role, version=version)
