"""Incremental synchronization of the library on disk with the database."""

from django.conf import settings
from django.utils import timezone
from django.utils.text import slugify

from library.models import Game, GameFile, LooseFile, ScanRun, System

from .grouping import group_system_dir
from .systems_map import lookup_system


def _find_game(system: System, group) -> Game | None:
    """A game's identity is its folder — matched verbatim against `Game.folder`."""
    return Game.objects.filter(folder=group.folder).first()


def _sync_group(system: System, group, run: ScanRun, seen: set[str]) -> None:
    game = _find_game(system, group)
    if game is None:
        game = Game.objects.create(
            system=system,
            folder=group.folder,
            title=group.title,
            normalized_title=group.normalized_title,
            switch_title_prefix=group.switch_title_prefix,
        )
        run.games_created += 1
    elif group.switch_title_prefix and game.switch_title_prefix != group.switch_title_prefix:
        game.switch_title_prefix = group.switch_title_prefix
        game.save(update_fields=["switch_title_prefix"])
    for entry in group.files:
        seen.add(entry.relative_path)
        existing = GameFile.objects.filter(relative_path=entry.relative_path).first()
        if existing is None:
            GameFile.objects.create(
                game=game,
                relative_path=entry.relative_path,
                role=entry.role,
                disc_number=entry.disc_number,
                version=entry.version,
                size=entry.size,
                mtime_ns=entry.mtime_ns,
            )
            run.files_created += 1
            continue
        fields: list[str] = []
        # Ten sam plik pod inną grą (np. po migracji, gdzie stara gra miała
        # głębszy folder) — przepinamy go, inaczej nowa gra co skan zostaje
        # pusta i leci do kasacji, a skan nigdy się nie zbiega.
        if existing.game_id != game.pk:
            existing.game = game
            fields.append("game")
        if (existing.size, existing.mtime_ns) != (entry.size, entry.mtime_ns):
            existing.size, existing.mtime_ns = entry.size, entry.mtime_ns
            fields += ["size", "mtime_ns"]
        # Reguły grupowania mogą się zmienić między wersjami (np. mods/ → rola
        # mod, DLC po title id) — skan musi przepisać metadane, nie tylko rozmiar.
        if (existing.role, existing.version, existing.disc_number) != (
            entry.role,
            entry.version,
            entry.disc_number,
        ):
            existing.role = entry.role
            existing.version = entry.version
            existing.disc_number = entry.disc_number
            fields += ["role", "version", "disc_number"]
        if fields:
            existing.save(update_fields=fields)
            run.files_updated += 1


def _sync_loose(all_loose: dict[str, tuple[System, int]]) -> None:
    """The set of `LooseFile` rows mirrors exactly the current scan."""
    existing = {lf.relative_path: lf for lf in LooseFile.objects.all()}
    for path, lf in existing.items():
        if path not in all_loose:
            lf.delete()
    for path, (system, size) in all_loose.items():
        lf = existing.get(path)
        if lf is None:
            LooseFile.objects.create(system=system, relative_path=path, size=size)
        elif lf.size != size or lf.system_id != system.pk:
            lf.size, lf.system = size, system
            lf.save(update_fields=["size", "system"])


def run_scan() -> ScanRun:
    run = ScanRun.objects.create()
    seen: set[str] = set()
    all_loose: dict[str, tuple[System, int]] = {}
    root = settings.LIBRARY_ROOT
    try:
        for system_dir in sorted(p for p in root.iterdir() if p.is_dir()):
            spec = lookup_system(system_dir.name)
            if spec:
                system, _ = System.objects.update_or_create(
                    directory=system_dir.name,
                    defaults={
                        "code": spec.code,
                        "name": spec.name,
                        "thumbnail_repo": spec.thumbnail_repo,
                    },
                )
                is_switch = spec.is_switch
            else:
                system, _ = System.objects.get_or_create(
                    directory=system_dir.name,
                    defaults={
                        "code": slugify(system_dir.name),
                        "name": system_dir.name,
                        "needs_config": True,
                    },
                )
                is_switch = False
            try:
                groups, loose = group_system_dir(system_dir, root, is_switch=is_switch)
                for group in groups:
                    _sync_group(system, group, run, seen)
                for entry in loose:
                    all_loose[entry.relative_path] = (system, entry.size)
            except OSError as exc:
                run.errors.append(f"{system_dir.name}: {exc}")
        _sync_loose(all_loose)
        run.loose_files = len(all_loose)
        # The difference is computed in Python — `exclude(relative_path__in=seen)`
        # exceeds SQLite's query parameter limit on a large library.
        stale_ids = [
            pk
            for pk, path in GameFile.objects.values_list("pk", "relative_path")
            if path not in seen
        ]
        run.files_deleted = len(stale_ids)
        for i in range(0, len(stale_ids), 500):
            GameFile.objects.filter(pk__in=stale_ids[i : i + 500]).delete()
        Game.objects.filter(files__isnull=True).delete()
        run.status = ScanRun.Status.SUCCESS
    except Exception as exc:  # the whole scan failed
        run.status = ScanRun.Status.FAILED
        run.errors.append(str(exc))
    run.finished_at = timezone.now()
    run.save()
    return run
