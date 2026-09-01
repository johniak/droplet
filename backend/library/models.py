from django.db import models


class System(models.Model):
    """A first-level directory in the library, e.g. `snes`."""

    code = models.SlugField(unique=True)
    name = models.CharField(max_length=200)
    directory = models.CharField(max_length=255, unique=True)
    thumbnail_repo = models.CharField(max_length=255, blank=True)
    needs_config = models.BooleanField(default=False)
    sort_order = models.IntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "name"]

    def __str__(self) -> str:
        return self.name


class Game(models.Model):
    system = models.ForeignKey(System, on_delete=models.CASCADE, related_name="games")
    title = models.CharField(max_length=500)
    normalized_title = models.CharField(max_length=500, db_index=True)
    switch_title_prefix = models.CharField(max_length=12, blank=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["title"]
        constraints = [
            models.UniqueConstraint(
                fields=["system", "normalized_title"], name="uniq_game_per_system"
            )
        ]

    def __str__(self) -> str:
        return self.title


class GameFile(models.Model):
    class Role(models.TextChoices):
        BASE = "base"
        UPDATE = "update"
        DLC = "dlc"
        DISC = "disc"
        SUPPORT = "support"
        OTHER = "other"

    game = models.ForeignKey(Game, on_delete=models.CASCADE, related_name="files")
    relative_path = models.CharField(max_length=1000, unique=True)
    role = models.CharField(max_length=10, choices=Role.choices, default=Role.BASE)
    disc_number = models.PositiveIntegerField(null=True, blank=True)
    version = models.CharField(max_length=50, blank=True)
    size = models.BigIntegerField()
    mtime_ns = models.BigIntegerField()

    class Meta:
        ordering = ["relative_path"]

    def __str__(self) -> str:
        return self.relative_path


class ScanRun(models.Model):
    class Status(models.TextChoices):
        RUNNING = "running"
        SUCCESS = "success"
        FAILED = "failed"

    started_at = models.DateTimeField(auto_now_add=True)
    finished_at = models.DateTimeField(null=True, blank=True)
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.RUNNING
    )
    games_created = models.IntegerField(default=0)
    files_created = models.IntegerField(default=0)
    files_updated = models.IntegerField(default=0)
    files_deleted = models.IntegerField(default=0)
    errors = models.JSONField(default=list)

    class Meta:
        ordering = ["-started_at"]

    def __str__(self) -> str:
        return f"ScanRun {self.pk} ({self.status})"
