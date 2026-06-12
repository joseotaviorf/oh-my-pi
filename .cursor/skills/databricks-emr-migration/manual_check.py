"""Helpers for tables that exceed runtime limits — skip compare, flag for human review."""

from __future__ import annotations

MANUAL_CHECK_STATUS = "MANUAL_CHECK"
MANUAL_CHECK_PREFIX = "Manual check required:"
TIMEOUT_PREFIX = "Command timeout after"


def is_manual_check_error(message: str | None) -> bool:
    if not message:
        return False
    msg_lower = message.lower()
    return (
        MANUAL_CHECK_PREFIX.lower() in msg_lower
        or TIMEOUT_PREFIX.lower() in msg_lower
    )


def manual_check_message(reason: str) -> str:
    reason = reason.strip()
    if reason.startswith(MANUAL_CHECK_PREFIX):
        return reason
    return f"{MANUAL_CHECK_PREFIX} {reason}"
