"""Extract Trino session user from an OAuth JWT (claims only, no signature check)."""

from __future__ import annotations

import base64
import json
import re
from typing import Any

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class IdentityError(ValueError):
    """Raised when a Trino user cannot be derived from the OAuth token."""


def _b64url_decode(segment: str) -> bytes:
    padding = "=" * ((4 - len(segment) % 4) % 4)
    return base64.urlsafe_b64decode(segment + padding)


def jwt_payload(token: str) -> dict[str, Any]:
    parts = token.split(".")
    if len(parts) != 3:
        raise IdentityError(
            "OAuth token is not a JWT (expected three segments). "
            "Cannot derive Trino user from an opaque token."
        )
    try:
        raw = _b64url_decode(parts[1])
        payload = json.loads(raw.decode("utf-8"))
    except (ValueError, json.JSONDecodeError) as exc:
        raise IdentityError("OAuth JWT payload is not valid JSON.") from exc
    if not isinstance(payload, dict):
        raise IdentityError("OAuth JWT payload is not an object.")
    return payload


def _looks_like_email(value: str) -> bool:
    return bool(_EMAIL_RE.match(value))


def trino_user_from_oauth_token(token: str) -> str:
    """Pick email, else preferred_username/upn, else email-like sub."""
    claims = jwt_payload(token)
    email = claims.get("email")
    if isinstance(email, str) and email.strip():
        return email.strip()
    for key in ("preferred_username", "upn"):
        value = claims.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    sub = claims.get("sub")
    if isinstance(sub, str) and _looks_like_email(sub.strip()):
        return sub.strip()
    raise IdentityError(
        "OAuth JWT has no usable identity claim "
        "(email, preferred_username, upn, or email-like sub)."
    )
