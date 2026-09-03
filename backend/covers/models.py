from django.db import models


class Cover(models.Model):
    class Source(models.TextChoices):
        LIBRETRO = "libretro"
        TITLEDB = "titledb"
        MANUAL = "manual"

    game = models.OneToOneField(
        "library.Game", on_delete=models.CASCADE, related_name="cover"
    )
    source = models.CharField(max_length=10, choices=Source.choices)
    match_name = models.CharField(max_length=500, blank=True)
    score = models.FloatField(default=0)
    is_manual = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"Cover({self.game_id}, {self.match_name or '-'})"
