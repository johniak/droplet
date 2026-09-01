"""Group the files of one system directory into games.

Pure filesystem logic — no ORM — so it can be tested on temporary trees.
"""

from dataclasses import dataclass, field
from pathlib import Path

from .naming import display_title, normalize_title
from .playlists import parse_cue, parse_m3u
from .switch import parse_switch, title_prefix


@dataclass
class FileEntry:
    relative_path: str
    role: str
    disc_number: int | None
    version: str
    size: int
    mtime_ns: int


@dataclass
class GameGroup:
    title: str
    normalized_title: str
    switch_title_prefix: str = ""
    files: list[FileEntry] = field(default_factory=list)


def _entry(path: Path, root: Path, role: str, disc=None, version="") -> FileEntry:
    st = path.stat()
    return FileEntry(
        relative_path=path.relative_to(root).as_posix(),
        role=role,
        disc_number=disc,
        version=version,
        size=st.st_size,
        mtime_ns=st.st_mtime_ns,
    )


def group_system_dir(
    system_dir: Path, library_root: Path, *, is_switch: bool
) -> list[GameGroup]:
    all_files = sorted(
        p
        for p in system_dir.rglob("*")
        if p.is_file()
        and not any(part.startswith(".") for part in p.relative_to(library_root).parts)
    )
    file_set = set(all_files)
    claimed: set[Path] = set()
    groups: list[GameGroup] = []

    def resolve(base: Path, name: str) -> Path | None:
        cand = base.parent / name
        return cand if cand in file_set else None

    # 1. m3u playlists: one multi-disc game
    for m3u in [p for p in all_files if p.suffix.lower() == ".m3u"]:
        group = GameGroup(
            title=display_title(m3u.stem), normalized_title=normalize_title(m3u.stem)
        )
        group.files.append(_entry(m3u, library_root, "support"))
        claimed.add(m3u)
        for i, name in enumerate(parse_m3u(m3u.read_text(errors="replace")), start=1):
            disc = resolve(m3u, name)
            if disc is None:
                continue
            group.files.append(_entry(disc, library_root, "disc", disc=i))
            claimed.add(disc)
            if disc.suffix.lower() == ".cue":
                for bin_name in parse_cue(disc.read_text(errors="replace")):
                    b = resolve(disc, bin_name)
                    if b is not None:
                        group.files.append(_entry(b, library_root, "support"))
                        claimed.add(b)
        groups.append(group)

    # 2. standalone cue sheets
    for cue in [p for p in all_files if p.suffix.lower() == ".cue" and p not in claimed]:
        group = GameGroup(
            title=display_title(cue.stem), normalized_title=normalize_title(cue.stem)
        )
        group.files.append(_entry(cue, library_root, "base"))
        claimed.add(cue)
        for bin_name in parse_cue(cue.read_text(errors="replace")):
            b = resolve(cue, bin_name)
            if b is not None and b not in claimed:
                group.files.append(_entry(b, library_root, "support"))
                claimed.add(b)
        groups.append(group)

    rest = [p for p in all_files if p not in claimed]

    # 3. switch: group base + updates + DLC by title id family
    if is_switch:
        families: dict[str, GameGroup] = {}
        for p in rest:
            info = parse_switch(p.stem)
            key = (
                title_prefix(info.title_id)
                if info.title_id
                else normalize_title(p.stem)
            )
            group = families.setdefault(
                key,
                GameGroup(
                    title=display_title(p.stem),
                    normalized_title=normalize_title(p.stem),
                    switch_title_prefix=key if info.title_id else "",
                ),
            )
            if info.role == "base":
                group.title = display_title(p.stem)
                group.normalized_title = normalize_title(p.stem)
            group.files.append(_entry(p, library_root, info.role, version=info.version))
        groups.extend(families.values())
        return groups

    # 4. everything else: one file = one game
    for p in rest:
        groups.append(
            GameGroup(
                title=display_title(p.stem),
                normalized_title=normalize_title(p.stem),
                files=[_entry(p, library_root, "base")],
            )
        )
    return groups
