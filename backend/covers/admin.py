from django import forms
from django.contrib import admin

from .models import Cover
from .paths import full_path
from .service import _make_thumb
from .thumbnails import download_boxart


class CoverForm(forms.ModelForm):
    upload = forms.FileField(required=False, help_text="Własny plik okładki (PNG/JPG)")

    class Meta:
        model = Cover
        fields = ["match_name", "is_manual"]


@admin.register(Cover)
class CoverAdmin(admin.ModelAdmin):
    form = CoverForm
    list_display = ["game", "source", "match_name", "score", "is_manual", "updated_at"]
    list_filter = ["source", "is_manual"]
    search_fields = ["game__title", "match_name"]
    actions = ["refetch_from_match_name"]

    def save_model(self, request, obj, form, change):
        upload = form.cleaned_data.get("upload")
        if upload:
            from PIL import Image

            img = Image.open(upload).convert("RGB")
            dest = full_path(obj.game_id)
            dest.parent.mkdir(parents=True, exist_ok=True)
            img.save(dest, format="PNG")
            _make_thumb(obj.game_id)
            obj.source = Cover.Source.MANUAL
            obj.is_manual = True
        super().save_model(request, obj, form, change)

    @admin.action(description="Pobierz ponownie wg match_name (i zablokuj automat)")
    def refetch_from_match_name(self, request, queryset):
        for cover in queryset.select_related("game__system"):
            download_boxart(
                cover.game.system.thumbnail_repo,
                cover.match_name,
                full_path(cover.game_id),
            )
            _make_thumb(cover.game_id)
            cover.source = Cover.Source.MANUAL
            cover.is_manual = True
            cover.save()
        self.message_user(request, f"Odświeżono {queryset.count()} okładek")
