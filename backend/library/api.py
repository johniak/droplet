from django.db.models import Count
from rest_framework.decorators import api_view
from rest_framework.generics import ListAPIView
from rest_framework.response import Response

from .models import System
from .serializers import SystemSerializer
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
