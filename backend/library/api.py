from rest_framework.decorators import api_view
from rest_framework.response import Response

from .tasks import scan_library


@api_view(["POST"])
def trigger_scan(request):
    scan_library.enqueue()
    return Response({"enqueued": True}, status=202)
