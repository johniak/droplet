from django.contrib import admin
from django.shortcuts import redirect
from django.urls import path, reverse
from django.views.decorators.http import require_POST
from django.db.models import Count

from .models import Game, GameFile, LooseFile, ScanRun, System
from .tasks import scan_library


@admin.register(System)
class SystemAdmin(admin.ModelAdmin):
    list_display = ["code", "name", "directory", "thumbnail_repo", "needs_config", "loose_count"]
    list_editable = ["thumbnail_repo", "needs_config"]
    list_filter = ["needs_config"]

    def get_queryset(self, request):
        return super().get_queryset(request).annotate(_loose=Count("loose_files"))

    @admin.display(description="luzem", ordering="_loose")
    def loose_count(self, obj):
        return obj._loose


class HasCoverFilter(admin.SimpleListFilter):
    title = "okładka"
    parameter_name = "has_cover"

    def lookups(self, request, model_admin):
        return [("yes", "jest"), ("no", "brak")]

    def queryset(self, request, queryset):
        if self.value() == "yes":
            return queryset.filter(cover__isnull=False)
        if self.value() == "no":
            return queryset.filter(cover__isnull=True)
        return queryset


class GameFileInline(admin.TabularInline):
    model = GameFile
    fields = ["relative_path", "role", "disc_number", "version", "size"]
    readonly_fields = ["relative_path", "size"]
    extra = 0


@admin.register(Game)
class GameAdmin(admin.ModelAdmin):
    list_display = ["title", "system", "folder", "file_count"]
    list_filter = ["system", HasCoverFilter]
    search_fields = ["title", "normalized_title", "folder"]
    inlines = [GameFileInline]
    actions = ["show_cover_candidates"]

    @admin.action(description="Pokaż kandydatów okładki (top 5)")
    def show_cover_candidates(self, request, queryset):
        from covers.matching import top_candidates
        from covers.thumbnails import fetch_index

        for game in queryset.select_related("system")[:10]:
            names = fetch_index(game.system.thumbnail_repo)
            tops = top_candidates(game.normalized_title, names)
            listing = "; ".join(f"{t.name} ({t.score:.0f})" for t in tops)
            self.message_user(request, f"{game.title}: {listing}")

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
        "loose_files",
    ]
    actions = ["run_scan_action"]

    @admin.action(description="Uruchom skan biblioteki")
    def run_scan_action(self, request, queryset):
        scan_library.enqueue()
        self.message_user(request, "Skan dodany do kolejki")

    # Akcje Django wymagają zaznaczonych wierszy, a przy świeżej bazie lista
    # jest pusta — przycisk „Skanuj teraz” w pasku narzędzi działa zawsze.
    def get_urls(self):
        custom = [
            path(
                "scan-now/",
                self.admin_site.admin_view(require_POST(self.scan_now)),
                name="library_scanrun_scan_now",
            )
        ]
        return custom + super().get_urls()

    def scan_now(self, request):
        scan_library.enqueue()
        self.message_user(request, "Skan dodany do kolejki")
        return redirect(reverse("admin:library_scanrun_changelist"))


@admin.register(LooseFile)
class LooseFileAdmin(admin.ModelAdmin):
    list_display = ["relative_path", "hint", "system", "size"]
    list_filter = ["system"]
    search_fields = ["relative_path"]
    readonly_fields = ["system", "relative_path", "size"]

    @admin.display(description="co zrobić")
    def hint(self, obj):
        if obj.relative_path.endswith("/"):
            return "rozpakowany mod — spakuj do zipa w mods/"
        if "/mods/" in obj.relative_path:
            return "mod bez gry — dodaj pliki gry do tego folderu"
        return "przenieś do katalogu gry"

    # Widok wyłącznie do podglądu: wiersze są lustrem skanu, więc ręczna edycja
    # albo kasowanie i tak zniknęłyby przy najbliższym przebiegu.
    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
