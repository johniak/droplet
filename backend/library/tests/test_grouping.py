from library.scanner.grouping import SIDECAR_EXTENSIONS, group_system_dir


def _write(p, content=b"x"):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(content)


def _by_title(groups):
    return {g.title: g for g in groups}


def test_each_folder_is_one_game_and_loose_files_are_reported(tmp_path):
    root = tmp_path
    _write(root / "snes" / "Super Mario World (USA)" / "Super Mario World (USA).sfc")
    _write(root / "snes" / "F-Zero (USA)" / "F-Zero (USA).sfc")
    _write(root / "snes" / "Loose (USA).sfc", b"loose")
    _write(root / "snes" / ".hidden" / "x.sfc")
    groups, loose = group_system_dir(root / "snes", root, is_switch=False)
    assert sorted(g.folder for g in groups) == ["snes/F-Zero (USA)", "snes/Super Mario World (USA)"]
    g = _by_title(groups)["Super Mario World"]
    assert g.normalized_title == "super mario world"
    assert g.files[0].relative_path == "snes/Super Mario World (USA)/Super Mario World (USA).sfc"
    assert g.files[0].role == "base"
    assert [(l.relative_path, l.size) for l in loose] == [("snes/Loose (USA).sfc", 5)]


def test_title_comes_from_folder_not_files(tmp_path):
    root = tmp_path
    _write(root / "gba" / "Metroid Fusion (USA)" / "mf.gba")
    _write(root / "gba" / "Metroid Fusion (USA)" / "readme.txt")
    groups, _ = group_system_dir(root / "gba", root, is_switch=False)
    g = groups[0]
    assert g.title == "Metroid Fusion"
    roles = {f.relative_path.split("/")[-1]: f.role for f in g.files}
    assert roles == {"mf.gba": "base", "readme.txt": "other"}
    assert ".txt" in SIDECAR_EXTENSIONS


def test_cue_bin_inside_folder(tmp_path):
    root = tmp_path
    d = root / "psx" / "Tekken (USA)"
    _write(d / "Tekken (USA).cue", b'FILE "Tekken (USA).bin" BINARY\n')
    _write(d / "Tekken (USA).bin")
    groups, _ = group_system_dir(root / "psx", root, is_switch=False)
    roles = {f.relative_path.split("/")[-1]: f.role for f in groups[0].files}
    assert roles == {"Tekken (USA).cue": "base", "Tekken (USA).bin": "support"}


def test_m3u_multidisc_inside_folder_with_subdirs(tmp_path):
    root = tmp_path
    d = root / "psx" / "FF7"
    _write(d / "disc1" / "FF7 (Disc 1).cue", b'FILE "FF7 (Disc 1).bin" BINARY\n')
    _write(d / "disc1" / "FF7 (Disc 1).bin")
    _write(d / "disc2" / "FF7 (Disc 2).cue", b'FILE "FF7 (Disc 2).bin" BINARY\n')
    _write(d / "disc2" / "FF7 (Disc 2).bin")
    _write(d / "FF7.m3u", b"disc1/FF7 (Disc 1).cue\ndisc2/FF7 (Disc 2).cue\n")
    groups, _ = group_system_dir(root / "psx", root, is_switch=False)
    assert len(groups) == 1
    discs = sorted((f.disc_number, f.relative_path) for f in groups[0].files if f.role == "disc")
    assert discs == [(1, "psx/FF7/disc1/FF7 (Disc 1).cue"), (2, "psx/FF7/disc2/FF7 (Disc 2).cue")]
    assert sum(1 for f in groups[0].files if f.role == "support") == 3  # m3u + 2 bin


def test_m3u_missing_entry_is_skipped(tmp_path):
    root = tmp_path
    d = root / "psx" / "Game"
    _write(d / "Game (Disc 1).cue", b'FILE "Game (Disc 1).bin" BINARY\n')
    _write(d / "Game (Disc 1).bin")
    _write(d / "Game.m3u", b"Game (Disc 1).cue\nGame (Disc 2).cue\n")
    groups, _ = group_system_dir(root / "psx", root, is_switch=False)
    assert [f.disc_number for f in groups[0].files if f.role == "disc"] == [1]


def test_switch_folder_roles_and_prefix(tmp_path):
    root = tmp_path
    d = root / "switch" / "Hollow Knight"
    _write(d / "Hollow Knight [0100633007D48000][v0].nsp")
    _write(d / "Hollow Knight [UPD][0100633007D48800][v196608].nsp")
    _write(d / "Hollow Knight [DLC][0100633007D49001].nsp")
    groups, _ = group_system_dir(root / "switch", root, is_switch=True)
    g = groups[0]
    assert g.title == "Hollow Knight"
    assert g.switch_title_prefix == "0100633007D4"
    roles = sorted((f.role, f.version) for f in g.files)
    assert roles == [("base", "v0"), ("dlc", ""), ("update", "v196608")]


def test_switch_folder_without_base_has_no_prefix(tmp_path):
    root = tmp_path
    _write(root / "switch" / "Only Update" / "X [UPD][0100633007D48800][v1].nsp")
    groups, _ = group_system_dir(root / "switch", root, is_switch=True)
    assert groups[0].switch_title_prefix == ""
    assert groups[0].files[0].role == "update"


def test_empty_folder_yields_no_game(tmp_path):
    (tmp_path / "snes" / "Empty").mkdir(parents=True)
    groups, loose = group_system_dir(tmp_path / "snes", tmp_path, is_switch=False)
    assert groups == [] and loose == []


def test_switch_folder_sidecar_files_are_other(tmp_path):
    root = tmp_path
    d = root / "switch" / "Game"
    _write(d / "Game [0100633007D48000][v0].nsp")
    _write(d / "cover.jpg")
    groups, _ = group_system_dir(root / "switch", root, is_switch=True)
    roles = {f.role for f in groups[0].files}
    assert roles == {"base", "other"}


def test_m3u_overlap_disc_guard_and_folder_wide_numbering(tmp_path):
    root = tmp_path
    d = root / "psx" / "Game"
    _write(d / "Disc1.cue", b'FILE "Disc1.bin" BINARY\n')
    _write(d / "Disc1.bin")
    _write(d / "Disc2.cue", b'FILE "Disc2.bin" BINARY\n')
    _write(d / "Disc2.bin")
    _write(d / "Disc3.cue", b'FILE "Disc3.bin" BINARY\n')
    _write(d / "Disc3.bin")
    _write(d / "A.m3u", b"Disc1.cue\nDisc2.cue\n")
    _write(d / "B.m3u", b"Disc2.cue\nDisc3.cue\n")
    groups, _ = group_system_dir(root / "psx", root, is_switch=False)
    discs = [f for f in groups[0].files if f.role == "disc"]
    assert sorted(f.relative_path.split("/")[-1] for f in discs) == [
        "Disc1.cue", "Disc2.cue", "Disc3.cue",
    ]
    assert sorted(f.disc_number for f in discs) == [1, 2, 3]


def test_m3u_entry_with_windows_backslash_path(tmp_path):
    root = tmp_path
    d = root / "psx" / "FF7"
    _write(d / "disc1" / "FF7 (Disc 1).cue", b'FILE "FF7 (Disc 1).bin" BINARY\n')
    _write(d / "disc1" / "FF7 (Disc 1).bin")
    _write(d / "FF7.m3u", b"disc1\\FF7 (Disc 1).cue\n")
    groups, _ = group_system_dir(root / "psx", root, is_switch=False)
    discs = [f for f in groups[0].files if f.role == "disc"]
    assert discs[0].relative_path == "psx/FF7/disc1/FF7 (Disc 1).cue"


def test_hidden_file_inside_game_folder_is_skipped(tmp_path):
    root = tmp_path
    d = root / "snes" / "Game"
    _write(d / "Game.sfc")
    _write(d / ".DS_Store")
    groups, _ = group_system_dir(root / "snes", root, is_switch=False)
    assert len(groups[0].files) == 1
    assert groups[0].files[0].relative_path.endswith("Game.sfc")


def test_nested_subdirectory_without_playlist(tmp_path):
    root = tmp_path
    d = root / "snes" / "Game"
    _write(d / "extras" / "manual.pdf")
    _write(d / "extras" / "rom.sfc")
    groups, _ = group_system_dir(root / "snes", root, is_switch=False)
    roles = {f.relative_path.split("/")[-1]: f.role for f in groups[0].files}
    assert roles == {"manual.pdf": "other", "rom.sfc": "base"}
