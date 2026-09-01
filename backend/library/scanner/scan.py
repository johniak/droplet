"""Incremental synchronization of the library on disk with the database."""

from django.conf import settings
from django.utils import timezone
from django.utils.text import slugify

from library.models import Game, GameFile, ScanRun, System

from .grouping import group_system_dir
from .systems_map import lookup_system


def _find_game(system: System, group) -> Game | None:
    """Match by title id first (Switch), then by normalized title.

    The title fallback is required: a group with a title id and a group without
    one (e.g. an update named without the tag) share a normalized_title, and
    UniqueConstraint (system, normalized_title) forbids two games.
    """
    if group.switch_title_prefix:
        game = Game.objects.filter(
            system=system, switch_title_prefix=group.switch_title_prefix
        ).first()
        if game is not None:
            return game
    game = Game.objects.filter(
        system=system, normalized_title=group.normalized_title
    ).first()
    if game is not None and group.switch_title_prefix and not game.switch_title_prefix:
        game.switch_title_prefix = group.switch_title_prefix
        game.save(update_fields=["switch_title_prefix"])
    return game


def _sync_group(system: System, group, run: ScanRun, seen: set[str]) -> None:
    game = _find_game(system, group)
    if game is None:
        game = Game.objects.create(
            system=system,
            title=group.title,
            normalized_title=group.normalized_title,
            switch_title_prefix=group.switch_title_prefix,
        )
        run.games_created += 1
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
        elif (existing.size, existing.mtime_ns) != (entry.size, entry.mtime_ns):
            existing.size, existing.mtime_ns = entry.size, entry.mtime_ns
            existing.save(update_fields=["size", "mtime_ns"])
            run.files_updated += 1


def run_scan() -> ScanRun:
    run = ScanRun.objects.create()
    seen: set[str] = set()
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
                for group in group_system_dir(system_dir, root, is_switch=is_switch):
                    _sync_group(system, group, run, seen)
            except OSError as exc:
                run.errors.append(f"{system_dir.name}: {exc}")
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
