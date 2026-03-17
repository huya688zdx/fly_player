from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from mitmproxy import ctx, http


OUTPUT_DIR = Path(r"E:\Android Project\fly_player\capture")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
LOG_PATH = OUTPUT_DIR / "fn_connect_capture.log"

TARGET_HOST_KEYWORDS = (
    "fnos.net",
    "trim",
    "media",
    "aliyuncs.com",
)

TARGET_PATH_KEYWORDS = (
    "/api/v1/fn/con",
    "/v/api/",
    "/trimcon",
    "/login",
)


def _match(flow: http.HTTPFlow) -> bool:
    host = flow.request.pretty_host.lower()
    path = flow.request.path.lower()
    return any(key in host for key in TARGET_HOST_KEYWORDS) or any(
        key in path for key in TARGET_PATH_KEYWORDS
    )


def _text_or_hex(data: bytes, limit: int = 4000) -> str:
    if not data:
        return ""
    sample = data[:limit]
    try:
        return sample.decode("utf-8", errors="replace")
    except Exception:
        return sample.hex()


def _append(record: dict) -> None:
    with LOG_PATH.open("a", encoding="utf-8") as fp:
        fp.write(json.dumps(record, ensure_ascii=False) + "\n")


class FnConnectCapture:
    def load(self, loader):
        ctx.log.info(f"writing capture log to {LOG_PATH}")

    def response(self, flow: http.HTTPFlow) -> None:
        if not _match(flow):
            return
        request = flow.request
        response = flow.response
        record = {
            "time": datetime.now().isoformat(timespec="seconds"),
            "method": request.method,
            "url": request.pretty_url,
            "host": request.pretty_host,
            "path": request.path,
            "request_headers": dict(request.headers),
            "request_body": _text_or_hex(request.raw_content or b""),
            "status_code": response.status_code if response else None,
            "response_headers": dict(response.headers) if response else {},
            "response_body": _text_or_hex(response.raw_content or b"")
            if response
            else "",
        }
        _append(record)
        ctx.log.info(f"{request.method} {request.pretty_url} -> {record['status_code']}")


addons = [FnConnectCapture()]
