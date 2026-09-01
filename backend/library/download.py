"""Serving ROM files with HTTP Range support (resumable downloads)."""

import posixpath
import re

from django.conf import settings
from django.http import Http404, HttpResponse, StreamingHttpResponse
from rest_framework.decorators import api_view
from rest_framework.generics import get_object_or_404

from .models import GameFile

CHUNK = 1024 * 1024
_RANGE = re.compile(r"^bytes=(\d+)-(\d*)$")


def _iter_file(path, start: int, length: int):
    with open(path, "rb") as f:
        f.seek(start)
        remaining = length
        while remaining > 0:
            chunk = f.read(min(CHUNK, remaining))
            if not chunk:
                return
            remaining -= len(chunk)
            yield chunk


@api_view(["GET"])
def file_download(request, pk: int):
    gf = get_object_or_404(GameFile, pk=pk)
    path = (settings.LIBRARY_ROOT / gf.relative_path).resolve()
    library_root = settings.LIBRARY_ROOT.resolve()
    if not path.is_relative_to(library_root) or not path.is_file():
        raise Http404
    size = path.stat().st_size
    filename = posixpath.basename(gf.relative_path)
    range_header = request.headers.get("Range")

    if range_header:
        m = _RANGE.match(range_header.strip())
        if not m or int(m.group(1)) >= size:
            resp = HttpResponse(status=416)
            resp["Content-Range"] = f"bytes */{size}"
            return resp
        start = int(m.group(1))
        end = int(m.group(2)) if m.group(2) else size - 1
        end = min(end, size - 1)
        resp = StreamingHttpResponse(
            _iter_file(path, start, end - start + 1),
            status=206,
            content_type="application/octet-stream",
        )
        resp["Content-Range"] = f"bytes {start}-{end}/{size}"
        resp["Content-Length"] = str(end - start + 1)
    else:
        resp = StreamingHttpResponse(
            _iter_file(path, 0, size), content_type="application/octet-stream"
        )
        resp["Content-Length"] = str(size)

    resp["Accept-Ranges"] = "bytes"
    resp["Content-Disposition"] = f'attachment; filename="{filename}"'
    return resp
