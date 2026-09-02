"""Group one system directory into games: every sub-directory is one game.

Pure filesystem logic — no ORM — so it can be tested on temporary trees.
"""

from dataclasses import dataclass, field
from pathlib import Path

from .naming import display_title, normalize_title
from .playlists import parse_cue, parse_m3u
from .switch import parse_switch, title_prefix

SIDECAR_EXTENSIONS = frozenset(
    {".txt", ".nfo", ".md", ".jpg", ".jpeg", ".png", ".pdf", ".sav", ".srm",
     ".state", ".xml", ".json"}
)


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
    folder: str
    title: str
    normalized_title: str
    switch_title_prefix: str = ""
    files: list[FileEntry] = field(default_factory=list)


@dataclass
class LooseEntry:
    relative_path: str
    size: int


def _entry(path: Path, root: Path, role: str, disc=None, version="") -> FileEntry:
    st = path.stat()
    return FileEntry(
        relative_path=path.relative_to(root).as_posix(),
        role=role, disc_number=disc, version=version,
        size=st.st_size, mtime_ns=st.st_mtime_ns,
    )


def _hidden(path: Path, root: Path) -> bool:
    return any(part.startswith(".") for part in path.relative_to(root).parts)


def _group_folder(folder: Path, root: Path, *, is_switch: bool) -> GameGroup | None:
    files = sorted(p for p in folder.rglob("*") if p.is_file() and not _hidden(p, root))
    if not files:
        return None
    file_set = set(files)
    group = GameGroup(
        folder=folder.relative_to(root).as_posix(),
        title=display_title(folder.name),
        normalized_title=normalize_title(folder.name),
    )
    claimed: set[Path] = set()

    def resolve(base: Path, name: str) -> Path | None:
        cand = base.parent / name.replace("\\", "/")
        return cand if cand in file_set else None

    # 1. m3u: płyty z numerami (jeden licznik na cały folder), cue/bin jako support
    disc_counter = 0
    for m3u in [p for p in files if p.suffix.lower() == ".m3u"]:
        group.files.append(_entry(m3u, root, "support"))
        claimed.add(m3u)
        for name in parse_m3u(m3u.read_text(errors="replace")):
            disc = resolve(m3u, name)
            if disc is None or disc in claimed:
                continue
            disc_counter += 1
            group.files.append(_entry(disc, root, "disc", disc=disc_counter))
            claimed.add(disc)
            if disc.suffix.lower() == ".cue":
                for bin_name in parse_cue(disc.read_text(errors="replace")):
                    b = resolve(disc, bin_name)
                    if b is not None and b not in claimed:
                        group.files.append(_entry(b, root, "support"))
                        claimed.add(b)

    # 2. samodzielne cue
    for cue in [p for p in files if p.suffix.lower() == ".cue" and p not in claimed]:
        group.files.append(_entry(cue, root, "base"))
        claimed.add(cue)
        for bin_name in parse_cue(cue.read_text(errors="replace")):
            b = resolve(cue, bin_name)
            if b is not None and b not in claimed:
                group.files.append(_entry(b, root, "support"))
                claimed.add(b)

    # 3. reszta: sidecar jako other (nawet w folderze Switch), Switch wg tagów, inne jako base
    for p in files:
        if p in claimed:
            continue
        if p.suffix.lower() in SIDECAR_EXTENSIONS:
            group.files.append(_entry(p, root, "other"))
        elif is_switch:
            info = parse_switch(p.stem)
            if info.role == "base" and info.title_id and not group.switch_title_prefix:
                group.switch_title_prefix = title_prefix(info.title_id)
            group.files.append(_entry(p, root, info.role, version=info.version))
        else:
            group.files.append(_entry(p, root, "base"))
    return group


def group_system_dir(
    system_dir: Path, library_root: Path, *, is_switch: bool
) -> tuple[list[GameGroup], list[LooseEntry]]:
    groups: list[GameGroup] = []
    loose: list[LooseEntry] = []
    for child in sorted(system_dir.iterdir()):
        if _hidden(child, library_root):
            continue
        if child.is_dir():
            group = _group_folder(child, library_root, is_switch=is_switch)
            if group is not None:
                groups.append(group)
        elif child.is_file():
            loose.append(
                LooseEntry(child.relative_to(library_root).as_posix(), child.stat().st_size)
            )
    return groups, loose
