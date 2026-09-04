"""Helpers to build unsigned JWTs for identity tests."""

from __future__ import annotations

import base64
import json
from typing import Any


def make_jwt(payload: dict[str, Any]) -> str:
    header = (
        base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}')
        .rstrip(b"=")
        .decode("ascii")
    )
    body = (
        base64.urlsafe_b64encode(json.dumps(payload, separators=(",", ":")).encode())
        .rstrip(b"=")
        .decode("ascii")
    )
    return f"{header}.{body}.sig"
