"""GChat delivery for empty-partition findings (Spark / EMR safe)."""

from __future__ import annotations

from typing import Any

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.observability.monitoring.empty_partition import (
    finding_thread_key,
    format_finding_message,
)
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

logger = QuintoAndarLogger("gchat_notify")


def _truthy(value: str | bool | None) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def notify_empty_partition_findings(
    findings: list[dict[str, Any]],
    *,
    environment: str,
    gchat_webhook_url: str | None = None,
    dry_run: str | bool = False,
    force_send: str | bool = False,
) -> None:
    """Post GChat alerts for judged empty-partition findings (fail-safe)."""
    dry_run_flag = _truthy(dry_run)
    force_send_flag = _truthy(force_send)
    deliver = environment == "prod" or force_send_flag
    webhook_url = (gchat_webhook_url or "").strip() or None

    if not findings:
        logger.info("No empty-partition findings to notify.")
        return

    logger.info(
        "empty-partition notify: environment=%s deliver=%s force_send=%s "
        "dry_run=%s webhook_configured=%s findings=%s",
        environment,
        deliver,
        force_send_flag,
        dry_run_flag,
        "yes" if webhook_url else "no",
        len(findings),
    )

    for finding in findings:
        message_text = format_finding_message(finding)
        logger.info(message_text)
        if dry_run_flag or not deliver:
            continue
        if not webhook_url:
            logger.warning("GChat webhook not configured; skipping send.")
            continue
        GChatService.send_message(
            Message(
                content=message_text,
                destination=webhook_url,
                thread_key=finding_thread_key(finding),
            )
        )
