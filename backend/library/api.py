import django_filters
from django.db.models import BigIntegerField, Count, Exists, OuterRef, Sum, Value
from django.db.models.functions import Coalesce
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework.decorators import api_view
from rest_framework.filters import OrderingFilter, SearchFilter
from rest_framework.generics import ListAPIView, RetrieveAPIView
from rest_framework.response import Response

from covers.models import Cover

from .models import Game, System
from .serializers import GameDetailSerializer, GameListSerializer, SystemSerializer
from .tasks import scan_library


@api_view(["POST"])
def trigger_scan(request):
    scan_library.enqueue()
    return Response({"enqueued": True}, status=202)


class SystemListView(ListAPIView):
    serializer_class = SystemSerializer
    pagination_class = None

    def get_queryset(self):
        return (
            System.objects.annotate(game_count=Count("games"))
            .filter(game_count__gt=0)
            .order_by("sort_order", "name")
        )


def annotated_games():
    return Game.objects.select_related("system").annotate(
        has_cover=Exists(Cover.objects.filter(game=OuterRef("pk"))),
        # Explicit output_field: without it Django can raise
        # "Expression contains mixed types" (BigIntegerField vs IntegerField).
        total_size=Coalesce(
            Sum("files__size"), Value(0), output_field=BigIntegerField()
        ),
    )


class GameFilter(django_filters.FilterSet):
    system = django_filters.CharFilter(field_name="system__code")

    class Meta:
        model = Game
        fields = ["system"]


class GameListView(ListAPIView):
    serializer_class = GameListSerializer
    filter_backends = [DjangoFilterBackend, SearchFilter, OrderingFilter]
    filterset_class = GameFilter
    search_fields = ["title", "normalized_title"]
    ordering_fields = ["title", "id"]
    ordering = ["title"]

    def get_queryset(self):
        return annotated_games()


class GameDetailView(RetrieveAPIView):
    serializer_class = GameDetailSerializer

    def get_queryset(self):
        return annotated_games().prefetch_related("files")
