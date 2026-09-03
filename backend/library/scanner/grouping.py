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
class LooseEntry:
    relative_path: str
    size: int


@dataclass
class GameGroup:
    folder: str
    title: str
    normalized_title: str
    switch_title_prefix: str = ""
    files: list[FileEntry] = field(default_factory=list)
    loose: list[LooseEntry] = field(default_factory=list)


def _entry(path: Path, root: Path, role: str, disc=None, version="") -> FileEntry:
    st = path.stat()
    return FileEntry(
        relative_path=path.relative_to(root).as_posix(),
        role=role, disc_number=disc, version=version,
        size=st.st_size, mtime_ns=st.st_mtime_ns,
    )


def _hidden(path: Path, root: Path) -> bool:
    return any(part.startswith(".") for part in path.relative_to(root).parts)


MODS_DIR = "mods"

# Pliki metadanych frontendów (ES-DE, Cocoon) w katalogu systemu — nie są ani
# grą, ani bałaganem do uporządkowania.
FRONTEND_FILES = frozenset({"systeminfo.txt"})


def _mod_kind(path: Path, folder: Path) -> str | None:
    """`"file"` dla pliku bezpośrednio w `<gra>/mods/`, `"nested"` dla pliku
    głębiej w `mods/` (rozpakowany mod), `None` poza `mods/`."""
    rel = path.relative_to(folder).parts
    if len(rel) < 2 or rel[0].lower() != MODS_DIR:
        return None
    return "file" if len(rel) == 2 else "nested"


def _group_folder(folder: Path, root: Path, *, is_switch: bool) -> GameGroup | None:
    files = sorted(p for p in folder.rglob("*") if p.is_file() and not _hidden(p, root))
    mods = [p for p in files if _mod_kind(p, folder) == "file"]
    nested: dict[Path, int] = {}
    for p in files:
        if _mod_kind(p, folder) == "nested":
            top = folder / p.relative_to(folder).parts[0] / p.relative_to(folder).parts[1]
            nested[top] = nested.get(top, 0) + p.stat().st_size
    files = [p for p in files if _mod_kind(p, folder) is None]
    if not files and not mods and not nested:
        return None
    if not files:
        # Mod bez gry (folder z samym mods/) nie jest grą — spakowane mody
        # zgłaszamy do uporządkowania obok rozpakowanych.
        for p in mods:
            nested[p] = p.stat().st_size
        mods = []
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

    for p in mods:
        group.files.append(_entry(p, root, "mod"))
    for top, size in sorted(nested.items()):
        rel = top.relative_to(root).as_posix()
        group.loose.append(LooseEntry(rel if top.is_file() else rel + "/", size))
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
                loose.extend(group.loose)
                if group.files:
                    groups.append(group)
        elif child.is_file() and child.name.lower() not in FRONTEND_FILES:
            loose.append(
                LooseEntry(child.relative_to(library_root).as_posix(), child.stat().st_size)
            )
    return groups, loose
