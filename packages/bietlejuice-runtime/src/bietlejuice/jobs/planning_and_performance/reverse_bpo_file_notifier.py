from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.messaging_services.alert_channel_service import (
    AlertChannelService,
)
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.services.reverse_bpo_export_summary import build_summary_marker_path

LOGGER = QuintoAndarLogger("reverse_bpo_file_notifier")

DEFAULT_CHANNEL_KEYWORD = "BPO_REVERSE_ALERTS"


def record_saved_file_marker(
    dbutils,
    bucket: str,
    dag_name: str,
    dag_run_id: str,
    file_name: str,
) -> None:
    marker_path = build_summary_marker_path(bucket, dag_name, dag_run_id, file_name)
    try:
        dbutils.fs.put(marker_path, file_name, overwrite=True)
    except Exception as exc:
        LOGGER.warning(
            f"m=record_saved_file_marker, marker_path={marker_path}, "
            f"msg=Could not record summary marker, error={exc}"
        )


@dataclass(frozen=True)
class FileSizeComparison:
    current_size_bytes: int
    previous_size_bytes: Optional[int]
    is_greater_than_previous: Optional[bool]
    size_change_pct: Optional[float]
    previous_file_path: Optional[str]

    @property
    def comparison_text(self) -> str:
        if self.previous_size_bytes is None:
            return "sem arquivo do dia anterior para comparação"

        previous_size = format_file_size(self.previous_size_bytes)

        if self.size_change_pct is None:
            change_text = "variação indisponível"
        elif self.size_change_pct >= 0:
            change_text = f"+{self.size_change_pct:.1f}%"
        else:
            change_text = f"{self.size_change_pct:.1f}%"

        status = ""
        if self.is_greater_than_previous is True:
            status = " | maior que ontem"
        elif self.is_greater_than_previous is False:
            status = " | MENOR que ontem"

        return f"ontem: {previous_size} ({change_text}){status}"


def format_file_size(size_bytes: int) -> str:
    if size_bytes < 1024:
        return f"{size_bytes} B"
    if size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.1f} KB"
    if size_bytes < 1024 * 1024 * 1024:
        return f"{size_bytes / (1024 * 1024):.1f} MB"
    return f"{size_bytes / (1024 * 1024 * 1024):.2f} GB"


def build_previous_day_paths(
    s3_path: str, file_name: str, execution_date: datetime
) -> tuple[str, str]:
    previous_date = execution_date - timedelta(days=1)
    previous_year = previous_date.strftime("%Y")
    previous_month = previous_date.strftime("%m")
    previous_day = previous_date.strftime("%d")

    previous_s3_path = s3_path.replace(
        f"year={execution_date.strftime('%Y')}/"
        f"month={execution_date.strftime('%m')}/"
        f"day={execution_date.strftime('%d')}/",
        f"year={previous_year}/month={previous_month}/day={previous_day}/",
    )

    if file_name.endswith(".parquet"):
        table_prefix = file_name[: -len(".parquet")]
        date_suffix = (
            f"_{execution_date.strftime('%Y')}_"
            f"{execution_date.strftime('%m')}_"
            f"{execution_date.strftime('%d')}"
        )
        if table_prefix.endswith(date_suffix):
            table_name = table_prefix[: -len(date_suffix)]
            previous_file_name = (
                f"{table_name}_{previous_year}_{previous_month}_{previous_day}.parquet"
            )
        else:
            previous_file_name = file_name
    else:
        previous_file_name = file_name

    return previous_s3_path, f"{previous_s3_path}{previous_file_name}"


def get_file_size_bytes(dbutils, file_path: str) -> Optional[int]:
    try:
        parent_path, _, target_name = file_path.rpartition("/")
        if not parent_path:
            return None

        for file_info in dbutils.fs.ls(f"{parent_path}/"):
            if file_info.name == target_name:
                return int(file_info.size)
    except Exception as exc:
        LOGGER.warning(
            f"m=get_file_size_bytes, file_path={file_path}, msg=Could not read file size, error={exc}"
        )
        return None
    return None


def compare_with_previous_day(
    dbutils,
    current_size_bytes: int,
    s3_path: str,
    file_name: str,
    execution_date: datetime,
) -> FileSizeComparison:
    previous_s3_path, previous_file_path = build_previous_day_paths(
        s3_path=s3_path,
        file_name=file_name,
        execution_date=execution_date,
    )
    previous_size_bytes = get_file_size_bytes(dbutils, previous_file_path)

    if previous_size_bytes is None:
        return FileSizeComparison(
            current_size_bytes=current_size_bytes,
            previous_size_bytes=None,
            is_greater_than_previous=None,
            size_change_pct=None,
            previous_file_path=previous_file_path,
        )

    size_change_pct = (
        (current_size_bytes - previous_size_bytes) / previous_size_bytes
    ) * 100

    return FileSizeComparison(
        current_size_bytes=current_size_bytes,
        previous_size_bytes=previous_size_bytes,
        is_greater_than_previous=current_size_bytes > previous_size_bytes,
        size_change_pct=size_change_pct,
        previous_file_path=previous_file_path,
    )


def format_gchat_message(
    *,
    dag_name: str,
    file_name: str,
    saved_at: datetime,
    row_count: int,
    comparison: FileSizeComparison,
) -> str:
    status_icon = "✅"
    if comparison.is_greater_than_previous is False:
        status_icon = "⚠️"

    return (
        f"{status_icon} *{dag_name}* — arquivo salvo\n\n"
        f"📁 *Arquivo:* {file_name}\n"
        f"🕐 *Salvo em:* {saved_at.strftime('%Y-%m-%d %H:%M:%S')}\n"
        f"📊 *Linhas:* {row_count:,}\n"
        f"📈 *Tamanho:* {format_file_size(comparison.current_size_bytes)} "
        f"({comparison.comparison_text})"
    )


def notify_reverse_bpo_file_saved(
    *,
    dbutils,
    environment: str,
    dag_name: str,
    file_name: str,
    destination_path: str,
    s3_path: str,
    execution_date: datetime,
    row_count: int,
    dag_run_id: str,
    bucket: str,
    alert_channel: str = DEFAULT_CHANNEL_KEYWORD,
) -> bool:
    """
    Send a Google Chat notification after a reverse BPO parquet file is saved.

    Never raises: failures to resolve the webhook or send the message are logged and
    swallowed so export jobs are not blocked by alerting.
    """
    try:
        current_size_bytes = get_file_size_bytes(dbutils, destination_path)
        if current_size_bytes is None:
            LOGGER.warning(
                f"m=notify_reverse_bpo_file_saved, destination_path={destination_path}, "
                "msg=Skipping GChat notification because file size could not be read"
            )
            return False

        comparison = compare_with_previous_day(
            dbutils=dbutils,
            current_size_bytes=current_size_bytes,
            s3_path=s3_path,
            file_name=file_name,
            execution_date=execution_date,
        )
        message_content = format_gchat_message(
            dag_name=dag_name,
            file_name=file_name,
            saved_at=datetime.now(),
            row_count=row_count,
            comparison=comparison,
        )

        fallback_keyword = (
            "AE_ALERTS_PROD" if environment == "prod" else "AE_ALERTS_FORNO"
        )
        webhook_url = AlertChannelService(dbutils=dbutils).get_gchat_webhook_url(
            channel_keyword=alert_channel,
            default_keyword=fallback_keyword,
        )
        message = Message(content=message_content, destination=webhook_url)
        sent = GChatService.send_message(message)
        if sent:
            record_saved_file_marker(
                dbutils=dbutils,
                bucket=bucket,
                dag_name=dag_name,
                dag_run_id=dag_run_id,
                file_name=file_name,
            )
        else:
            LOGGER.warning(
                f"m=notify_reverse_bpo_file_saved, dag_name={dag_name}, "
                f"file_name={file_name}, msg=GChat notification was not delivered"
            )
        return sent
    except Exception as exc:
        LOGGER.warning(
            f"m=notify_reverse_bpo_file_saved, dag_name={dag_name}, "
            f"file_name={file_name}, msg=Failed to send GChat notification, error={exc}"
        )
        return False
