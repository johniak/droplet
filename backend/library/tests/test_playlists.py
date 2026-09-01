from library.scanner.playlists import parse_cue, parse_m3u

CUE = '''REM COMMENT
FILE "Game (Track 1).bin" BINARY
  TRACK 01 MODE2/2352
FILE "Game (Track 2).bin" BINARY
'''

M3U = """# playlist
Game (Disc 1).cue

Game (Disc 2).cue
"""


def test_parse_cue():
    assert parse_cue(CUE) == ["Game (Track 1).bin", "Game (Track 2).bin"]


def test_parse_m3u():
    assert parse_m3u(M3U) == ["Game (Disc 1).cue", "Game (Disc 2).cue"]
