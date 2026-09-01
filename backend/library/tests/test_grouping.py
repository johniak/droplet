from library.scanner.grouping import group_system_dir


def _write(p, content=b"x"):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(content)


def _by_title(groups):
    return {g.title: g for g in groups}


def test_single_files_become_games(tmp_path):
    root = tmp_path
    _write(root / "snes" / "Super Mario World (USA).sfc")
    _write(root / "snes" / "F-Zero (USA).sfc")
    groups = group_system_dir(root / "snes", root, is_switch=False)
    assert len(groups) == 2
    g = _by_title(groups)["Super Mario World"]
    assert g.files[0].relative_path == "snes/Super Mario World (USA).sfc"
    assert g.files[0].role == "base"


def test_cue_bin_is_one_game(tmp_path):
    root = tmp_path
    _write(root / "psx" / "Tekken (USA).cue", b'FILE "Tekken (USA).bin" BINARY\n')
    _write(root / "psx" / "Tekken (USA).bin")
    groups = group_system_dir(root / "psx", root, is_switch=False)
    assert len(groups) == 1
    roles = {f.relative_path.split("/")[-1]: f.role for f in groups[0].files}
    assert roles == {"Tekken (USA).cue": "base", "Tekken (USA).bin": "support"}


def test_m3u_multidisc(tmp_path):
    root = tmp_path
    d = root / "psx"
    _write(d / "FF7 (Disc 1).cue", b'FILE "FF7 (Disc 1).bin" BINARY\n')
    _write(d / "FF7 (Disc 1).bin")
    _write(d / "FF7 (Disc 2).cue", b'FILE "FF7 (Disc 2).bin" BINARY\n')
    _write(d / "FF7 (Disc 2).bin")
    _write(d / "FF7.m3u", b"FF7 (Disc 1).cue\nFF7 (Disc 2).cue\n")
    groups = group_system_dir(d, root, is_switch=False)
    assert len(groups) == 1
    discs = sorted(
        (f.disc_number, f.relative_path.split("/")[-1])
        for f in groups[0].files
        if f.role == "disc"
    )
    assert discs == [(1, "FF7 (Disc 1).cue"), (2, "FF7 (Disc 2).cue")]


def test_switch_family_grouped(tmp_path):
    root = tmp_path
    d = root / "switch"
    _write(d / "Hollow Knight [0100633007D48000][v0].nsp")
    _write(d / "Hollow Knight [UPD][0100633007D48800][v196608].nsp")
    _write(d / "Hollow Knight [DLC][0100633007D49001].nsp")
    _write(d / "Celeste [01002B30028F6000][v0].nsp")
    groups = group_system_dir(d, root, is_switch=True)
    assert len(groups) == 2
    hk = _by_title(groups)["Hollow Knight"]
    assert sorted(f.role for f in hk.files) == ["base", "dlc", "update"]
    upd = next(f for f in hk.files if f.role == "update")
    assert upd.version == "v196608"


def test_hidden_files_skipped(tmp_path):
    root = tmp_path
    _write(root / "snes" / ".DS_Store")
    assert group_system_dir(root / "snes", root, is_switch=False) == []


def test_m3u_missing_entry_is_skipped(tmp_path):
    root = tmp_path
    d = root / "psx"
    _write(d / "FF7 (Disc 1).cue", b'FILE "FF7 (Disc 1).bin" BINARY\n')
    _write(d / "FF7 (Disc 1).bin")
    _write(d / "FF7.m3u", b"FF7 (Disc 1).cue\nFF7 (Disc 2).cue\n")
    groups = group_system_dir(d, root, is_switch=False)
    assert len(groups) == 1
    assert [f.disc_number for f in groups[0].files if f.role == "disc"] == [1]


def test_switch_without_title_id_groups_by_title(tmp_path):
    root = tmp_path
    d = root / "switch"
    _write(d / "Celeste.nsp")
    _write(d / "Celeste (UPD) (v1.2.6).nsp")
    groups = group_system_dir(d, root, is_switch=True)
    assert len(groups) == 1
    assert sorted(f.role for f in groups[0].files) == ["base", "update"]
