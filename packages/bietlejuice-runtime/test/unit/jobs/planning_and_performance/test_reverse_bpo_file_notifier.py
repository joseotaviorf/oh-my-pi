import base64
from datetime import datetime
from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.jobs.planning_and_performance.reverse_bpo_file_notifier import (
    FileSizeComparison,
    build_previous_day_paths,
    compare_with_previous_day,
    format_file_size,
    format_gchat_message,
    get_file_size_bytes,
    normalize_gchat_webhook_url,
    notify_reverse_bpo_file_saved,
)

MODULE = "bietlejuice.jobs.planning_and_performance.reverse_bpo_file_notifier"


class TestFormatFileSize:
    @pytest.mark.parametrize(
        ("size_bytes", "expected"),
        [
            (512, "512 B"),
            (2048, "2.0 KB"),
            (5 * 1024 * 1024, "5.0 MB"),
            (3 * 1024 * 1024 * 1024, "3.00 GB"),
        ],
    )
    def test_formats_human_readable_sizes(self, size_bytes, expected):
        assert format_file_size(size_bytes) == expected


class TestBuildPreviousDayPaths:
    def test_builds_previous_partition_and_file_name(self):
        execution_date = datetime(2026, 8, 26)
        s3_path = "s3a://bucket/atento/cases_perspective/year=2026/month=08/day=26/"
        file_name = "cases_perspective_2026_08_26.parquet"

        previous_s3_path, previous_file_path = build_previous_day_paths(
            s3_path=s3_path,
            file_name=file_name,
            execution_date=execution_date,
        )

        assert previous_s3_path == (
            "s3a://bucket/atento/cases_perspective/year=2026/month=08/day=25/"
        )
        assert previous_file_path.endswith("cases_perspective_2026_08_25.parquet")


class TestFileSizeComparison:
    def test_comparison_text_when_previous_file_is_missing(self):
        comparison = FileSizeComparison(
            current_size_bytes=1024,
            previous_size_bytes=None,
            is_greater_than_previous=None,
            size_change_pct=None,
            previous_file_path="s3a://bucket/file.parquet",
        )

        assert (
            comparison.comparison_text == "sem arquivo do dia anterior para comparação"
        )

    def test_comparison_text_when_current_file_is_greater(self):
        comparison = FileSizeComparison(
            current_size_bytes=2200,
            previous_size_bytes=2000,
            is_greater_than_previous=True,
            size_change_pct=10.0,
            previous_file_path="s3a://bucket/file.parquet",
        )

        assert "maior que ontem" in comparison.comparison_text
        assert "+10.0%" in comparison.comparison_text

    def test_comparison_text_when_current_file_is_smaller(self):
        comparison = FileSizeComparison(
            current_size_bytes=1800,
            previous_size_bytes=2000,
            is_greater_than_previous=False,
            size_change_pct=-10.0,
            previous_file_path="s3a://bucket/file.parquet",
        )

        assert "MENOR que ontem" in comparison.comparison_text
        assert "-10.0%" in comparison.comparison_text


class TestGetFileSizeBytes:
    def test_returns_size_when_file_exists(self):
        dbutils = MagicMock()
        file_info = MagicMock()
        file_info.name = "file.parquet"
        file_info.size = 1234
        dbutils.fs.ls.return_value = [file_info]

        assert get_file_size_bytes(dbutils, "s3a://bucket/path/file.parquet") == 1234
        dbutils.fs.ls.assert_called_once_with("s3a://bucket/path/")

    def test_returns_none_when_file_is_missing(self):
        dbutils = MagicMock()
        dbutils.fs.ls.side_effect = Exception("path does not exist")

        assert get_file_size_bytes(dbutils, "s3a://bucket/missing.parquet") is None


class TestCompareWithPreviousDay:
    @patch(f"{MODULE}.get_file_size_bytes")
    def test_returns_comparison_when_previous_file_exists(self, mock_get_file_size):
        mock_get_file_size.return_value = 2000
        dbutils = MagicMock()
        execution_date = datetime(2026, 8, 26)

        comparison = compare_with_previous_day(
            dbutils=dbutils,
            current_size_bytes=2500,
            s3_path="s3a://bucket/atento/table/year=2026/month=08/day=26/",
            file_name="table_2026_08_26.parquet",
            execution_date=execution_date,
        )

        assert comparison.previous_size_bytes == 2000
        assert comparison.is_greater_than_previous is True
        assert comparison.size_change_pct == pytest.approx(25.0)


class TestFormatGchatMessage:
    def test_includes_file_metadata_and_comparison(self):
        comparison = FileSizeComparison(
            current_size_bytes=2500,
            previous_size_bytes=2000,
            is_greater_than_previous=True,
            size_change_pct=25.0,
            previous_file_path="s3a://bucket/table_2026_08_25.parquet",
        )

        message = format_gchat_message(
            dag_name="reverse_atento",
            file_name="table_2026_08_26.parquet",
            saved_at=datetime(2026, 8, 26, 7, 30, 15),
            row_count=15432,
            comparison=comparison,
        )

        assert "reverse_atento" in message
        assert "table_2026_08_26.parquet" in message
        assert "2026-08-26 07:30:15" in message
        assert "15,432" in message
        assert "maior que ontem" in message


class TestNormalizeGchatWebhookUrl:
    def test_leaves_plain_url_unchanged(self):
        url = "https://chat.googleapis.com/v1/spaces/TEST/messages?key=TEST"
        assert normalize_gchat_webhook_url(url) == url

    def test_decodes_base64_webhook_url(self):
        url = "https://chat.googleapis.com/v1/spaces/TEST/messages?key=TEST"
        encoded = base64.b64encode(url.encode("utf-8")).decode("ascii")
        assert normalize_gchat_webhook_url(encoded) == url


class TestNotifyReverseBpoFileSaved:
    @patch(f"{MODULE}.record_saved_file_marker")
    @patch(f"{MODULE}.GChatService.send_message", return_value=True)
    @patch(f"{MODULE}.AlertChannelService")
    @patch(f"{MODULE}.get_file_size_bytes")
    @patch(f"{MODULE}.compare_with_previous_day")
    def test_sends_message_with_primary_channel(
        self,
        mock_compare,
        mock_get_file_size,
        mock_alert_channel_service,
        mock_send_message,
        mock_record_marker,
    ):
        mock_get_file_size.return_value = 2500
        mock_compare.return_value = FileSizeComparison(
            current_size_bytes=2500,
            previous_size_bytes=2000,
            is_greater_than_previous=True,
            size_change_pct=25.0,
            previous_file_path="s3a://bucket/table_2026_08_25.parquet",
        )
        alert_service = MagicMock()
        alert_service.get_gchat_webhook_url.return_value = (
            "https://chat.googleapis.com/webhook"
        )
        mock_alert_channel_service.return_value = alert_service

        sent = notify_reverse_bpo_file_saved(
            dbutils=MagicMock(),
            environment="prod",
            dag_name="reverse_atento",
            file_name="table_2026_08_26.parquet",
            destination_path="s3a://bucket/table_2026_08_26.parquet",
            s3_path="s3a://bucket/atento/table/year=2026/month=08/day=26/",
            execution_date=datetime(2026, 8, 26),
            row_count=100,
            dag_run_id="manual__2026-08-26",
            bucket="5a-dataops-prod",
        )

        assert sent is True
        mock_record_marker.assert_called_once()
        alert_service.get_gchat_webhook_url.assert_called_once_with(
            channel_keyword="BPO_REVERSE_ALERTS",
            default_keyword="AE_ALERTS_PROD",
        )
        mock_send_message.assert_called_once()

    @patch(f"{MODULE}.record_saved_file_marker")
    @patch(f"{MODULE}.GChatService.send_message", return_value=True)
    @patch(f"{MODULE}.AlertChannelService")
    @patch(f"{MODULE}.get_file_size_bytes")
    @patch(f"{MODULE}.compare_with_previous_day")
    def test_decodes_base64_webhook_before_sending(
        self,
        mock_compare,
        mock_get_file_size,
        mock_alert_channel_service,
        mock_send_message,
        _mock_record_marker,
    ):
        mock_get_file_size.return_value = 2500
        mock_compare.return_value = FileSizeComparison(
            current_size_bytes=2500,
            previous_size_bytes=2000,
            is_greater_than_previous=True,
            size_change_pct=25.0,
            previous_file_path="s3a://bucket/table_2026_08_25.parquet",
        )
        plain_url = "https://chat.googleapis.com/v1/spaces/TEST/messages?key=TEST"
        encoded_url = base64.b64encode(plain_url.encode("utf-8")).decode("ascii")
        alert_service = MagicMock()
        alert_service.get_gchat_webhook_url.return_value = encoded_url
        mock_alert_channel_service.return_value = alert_service

        sent = notify_reverse_bpo_file_saved(
            dbutils=MagicMock(),
            environment="prod",
            dag_name="reverse_aec",
            file_name="table_2026_08_26.parquet",
            destination_path="s3a://bucket/table_2026_08_26.parquet",
            s3_path="s3a://bucket/aec/table/year=2026/month=08/day=26/",
            execution_date=datetime(2026, 8, 26),
            row_count=100,
            dag_run_id="manual__2026-08-26",
            bucket="5a-dataops-prod",
        )

        assert sent is True
        assert mock_send_message.call_args[0][0].destination == plain_url

    @patch(f"{MODULE}.get_file_size_bytes", return_value=None)
    def test_does_not_raise_when_file_size_is_unavailable(self, _mock_get_file_size):
        sent = notify_reverse_bpo_file_saved(
            dbutils=MagicMock(),
            environment="prod",
            dag_name="reverse_atento",
            file_name="table_2026_08_26.parquet",
            destination_path="s3a://bucket/table_2026_08_26.parquet",
            s3_path="s3a://bucket/atento/table/year=2026/month=08/day=26/",
            execution_date=datetime(2026, 8, 26),
            row_count=100,
            dag_run_id="manual__2026-08-26",
            bucket="5a-dataops-prod",
        )

        assert sent is False

    @patch(f"{MODULE}.GChatService.send_message", side_effect=RuntimeError("boom"))
    @patch(f"{MODULE}.AlertChannelService")
    @patch(f"{MODULE}.get_file_size_bytes", return_value=2500)
    @patch(f"{MODULE}.compare_with_previous_day")
    def test_swallows_send_failures(
        self,
        mock_compare,
        _mock_get_file_size,
        mock_alert_channel_service,
        _mock_send_message,
    ):
        mock_compare.return_value = FileSizeComparison(
            current_size_bytes=2500,
            previous_size_bytes=2000,
            is_greater_than_previous=True,
            size_change_pct=25.0,
            previous_file_path="s3a://bucket/table_2026_08_25.parquet",
        )
        alert_service = MagicMock()
        alert_service.get_gchat_webhook_url.return_value = (
            "https://chat.googleapis.com/webhook"
        )
        mock_alert_channel_service.return_value = alert_service

        sent = notify_reverse_bpo_file_saved(
            dbutils=MagicMock(),
            environment="forno",
            dag_name="reverse_aec",
            file_name="table_2026_08_26.parquet",
            destination_path="s3a://bucket/table_2026_08_26.parquet",
            s3_path="s3a://bucket/aec/table/year=2026/month=08/day=26/",
            execution_date=datetime(2026, 8, 26),
            row_count=100,
            dag_run_id="manual__2026-08-26",
            bucket="5a-dataops-forno",
        )

        assert sent is False
