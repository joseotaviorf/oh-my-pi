"""GChat delivery for observability findings (Spark / EMR safe)."""

from __future__ import annotations

from typing import Any, Callable

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.observability.monitoring.constants import (
    SIGNAL_EMPTY_PARTITION,
    SIGNAL_STALE_DATA,
)
from bietlejuice.observability.monitoring.empty_partition import (
    finding_thread_key as empty_partition_thread_key,
)
from bietlejuice.observability.monitoring.empty_partition import (
    format_finding_message as format_empty_partition_message,
)
from bietlejuice.observability.monitoring.stale_data import (
    finding_thread_key as stale_data_thread_key,
)
from bietlejuice.observability.monitoring.stale_data import (
    format_finding_message as format_stale_data_message,
)
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

logger = QuintoAndarLogger("gchat_notify")

_FORMATTERS: dict[str, Callable[[dict[str, Any]], str]] = {
    SIGNAL_EMPTY_PARTITION: format_empty_partition_message,
    SIGNAL_STALE_DATA: format_stale_data_message,
}
_THREAD_KEYS: dict[str, Callable[[dict[str, Any]], str]] = {
    SIGNAL_EMPTY_PARTITION: empty_partition_thread_key,
    SIGNAL_STALE_DATA: stale_data_thread_key,
}


def _truthy(value: str | bool | None) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def _format_finding(finding: dict[str, Any]) -> str:
    signal_type = str(finding.get("signal_type") or "")
    formatter = _FORMATTERS.get(signal_type)
    if formatter is None:
        return str(finding)
    return formatter(finding)


def _thread_key(finding: dict[str, Any]) -> str:
    signal_type = str(finding.get("signal_type") or "")
    key_fn = _THREAD_KEYS.get(signal_type)
    if key_fn is None:
        database = finding.get("database") or ""
        table = finding.get("table") or ""
        return f"{signal_type}:{database}.{table}"
    return key_fn(finding)


def notify_observability_findings(
    findings: list[dict[str, Any]],
    *,
    environment: str,
    gchat_webhook_url: str | None = None,
    dry_run: str | bool = False,
    force_send: str | bool = False,
) -> None:
    """Post GChat alerts for judged observability findings (fail-safe)."""
    dry_run_flag = _truthy(dry_run)
    force_send_flag = _truthy(force_send)
    deliver = environment == "prod" or force_send_flag
    webhook_url = (gchat_webhook_url or "").strip() or None

    if not findings:
        logger.info("No observability findings to notify.")
        return

    logger.info(
        "observability notify: environment=%s deliver=%s force_send=%s "
        "dry_run=%s webhook_configured=%s findings=%s",
        environment,
        deliver,
        force_send_flag,
        dry_run_flag,
        "yes" if webhook_url else "no",
        len(findings),
    )

    for finding in findings:
        message_text = _format_finding(finding)
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
                thread_key=_thread_key(finding),
            )
        )


def notify_empty_partition_findings(
    findings: list[dict[str, Any]],
    *,
    environment: str,
    gchat_webhook_url: str | None = None,
    dry_run: str | bool = False,
    force_send: str | bool = False,
) -> None:
    """Backward-compatible alias for empty-partition-only notification."""
    notify_observability_findings(
        findings,
        environment=environment,
        gchat_webhook_url=gchat_webhook_url,
        dry_run=dry_run,
        force_send=force_send,
    )
