from django.contrib import admin

from .models import Game, GameFile, ScanRun, System
from .tasks import scan_library


@admin.register(System)
class SystemAdmin(admin.ModelAdmin):
    list_display = ["code", "name", "directory", "thumbnail_repo", "needs_config"]
    list_editable = ["thumbnail_repo", "needs_config"]
    list_filter = ["needs_config"]


class GameFileInline(admin.TabularInline):
    model = GameFile
    fields = ["relative_path", "role", "disc_number", "version", "size"]
    readonly_fields = ["relative_path", "size"]
    extra = 0


@admin.register(Game)
class GameAdmin(admin.ModelAdmin):
    list_display = ["title", "system", "file_count"]
    list_filter = ["system"]
    search_fields = ["title", "normalized_title"]
    inlines = [GameFileInline]

    @admin.display(description="pliki")
    def file_count(self, obj):
        return obj.files.count()


@admin.register(GameFile)
class GameFileAdmin(admin.ModelAdmin):
    list_display = ["relative_path", "game", "role", "disc_number", "version", "size"]
    list_filter = ["role", "game__system"]
    search_fields = ["relative_path", "game__title"]
    autocomplete_fields = ["game"]
    list_editable = ["role"]


@admin.register(ScanRun)
class ScanRunAdmin(admin.ModelAdmin):
    list_display = [
        "started_at",
        "finished_at",
        "status",
        "games_created",
        "files_created",
        "files_updated",
        "files_deleted",
    ]
    actions = ["run_scan_action"]

    @admin.action(description="Uruchom skan biblioteki")
    def run_scan_action(self, request, queryset):
        scan_library.enqueue()
        self.message_user(request, "Skan dodany do kolejki")
