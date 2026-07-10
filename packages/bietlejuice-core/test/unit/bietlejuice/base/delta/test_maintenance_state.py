"""Unit tests for Delta maintenance S3 markers."""

import json
from datetime import date
from unittest.mock import MagicMock, patch

import pytest
from botocore.exceptions import ClientError

from bietlejuice.base.delta.maintenance_state import (
    build_maintenance_payload,
    build_marker_key,
    build_optimize_cursor_key,
    build_optimize_cursor_payload,
    days_since_last_optimize,
    is_optimize_due,
    maintenance_already_completed,
    normalize_s3_bucket,
    parse_iso_date,
    read_maintenance_marker,
    resolve_marker_location,
    resolve_optimize_cursor_location,
    slugify_full_table_name,
    write_maintenance_marker,
)

TEST_STATE_PREFIX = "bi-etl-ejuice/delta_maintenance"
TEST_REGION = "us-east-1"


class TestSlugifyFullTableName:
    def test_replaces_dot_with_double_underscore(self):
        # arrange
        full_table_name = "datalake_dw_braze.fact_events"

        # act
        slug = slugify_full_table_name(full_table_name)

        # assert
        assert slug == "datalake_dw_braze__fact_events"


class TestNormalizeS3Bucket:
    def test_plain_bucket_name(self):
        # arrange
        bucket = "my-bucket"

        # act
        normalized = normalize_s3_bucket(bucket)

        # assert
        assert normalized == "my-bucket"

    def test_strips_s3_uri_prefix(self):
        # arrange
        bucket_uri = "s3://artifacts.s3.data.quintoandar.com.br"

        # act
        normalized = normalize_s3_bucket(bucket_uri)

        # assert
        assert normalized == "artifacts.s3.data.quintoandar.com.br"

    def test_strips_key_path_after_bucket(self):
        # arrange
        bucket_uri = "s3://artifacts-bucket/some/prefix/key.json"

        # act
        normalized = normalize_s3_bucket(bucket_uri)

        # assert
        assert normalized == "artifacts-bucket"


class TestBuildMarkerKey:
    def test_builds_expected_key_layout(self):
        # arrange
        environment = "prod"
        full_table_name = "datalake_dw_braze.fact_events"
        maintenance_date = "2026-05-28"

        # act
        key = build_marker_key(
            environment=environment,
            full_table_name=full_table_name,
            maintenance_date=maintenance_date,
            state_prefix=TEST_STATE_PREFIX,
        )

        # assert
        assert (
            key
            == "bi-etl-ejuice/delta_maintenance/prod/datalake_dw_braze__fact_events/2026-05-28.json"
        )

    def test_custom_prefix(self):
        # arrange
        state_prefix = "custom/prefix"

        # act
        key = build_marker_key(
            environment="forno",
            full_table_name="datalake_clean.house",
            maintenance_date="2026-01-01",
            state_prefix=state_prefix,
        )

        # assert
        assert key.startswith("custom/prefix/forno/")

    def test_strips_leading_and_trailing_slashes_from_prefix(self):
        # act
        key = build_marker_key(
            environment="prod",
            full_table_name="db.table",
            maintenance_date="2026-05-28",
            state_prefix="/bi-etl-ejuice/delta_maintenance/",
        )

        # assert
        assert key.startswith("bi-etl-ejuice/delta_maintenance/prod/")


class TestReadMaintenanceMarker:
    @patch("bietlejuice.base.delta.maintenance_state.boto3")
    def test_returns_none_when_object_missing(self, mock_boto3):
        # arrange
        client = MagicMock()
        mock_boto3.client.return_value = client
        client.get_object.side_effect = ClientError(
            {"Error": {"Code": "NoSuchKey", "Message": "Not found"}},
            "GetObject",
        )

        # act
        result = read_maintenance_marker(
            "artifacts-bucket", "some/key", region_name=TEST_REGION
        )

        # assert
        assert result is None
        mock_boto3.client.assert_called_once_with("s3", region_name=TEST_REGION)

    @patch("bietlejuice.base.delta.maintenance_state.boto3")
    def test_returns_parsed_json_when_present(self, mock_boto3):
        # arrange
        payload = {"full_table_name": "db.t", "maintenance_date": "2026-05-28"}
        body = MagicMock()
        body.read.return_value = json.dumps(payload).encode("utf-8")
        client = MagicMock()
        mock_boto3.client.return_value = client
        client.get_object.return_value = {"Body": body}

        # act
        result = read_maintenance_marker(
            "s3://artifacts-bucket", "some/key", region_name=TEST_REGION
        )

        # assert
        assert result == payload
        client.get_object.assert_called_once_with(
            Bucket="artifacts-bucket", Key="some/key"
        )

    @patch("bietlejuice.base.delta.maintenance_state.boto3")
    def test_reraises_unexpected_client_errors(self, mock_boto3):
        # arrange
        client = MagicMock()
        mock_boto3.client.return_value = client
        client.get_object.side_effect = ClientError(
            {"Error": {"Code": "AccessDenied", "Message": "Forbidden"}},
            "GetObject",
        )

        # act / assert
        with pytest.raises(ClientError):
            read_maintenance_marker("bucket", "key", region_name=TEST_REGION)


class TestMaintenanceAlreadyCompleted:
    @patch("bietlejuice.base.delta.maintenance_state.read_maintenance_marker")
    def test_true_when_marker_exists(self, mock_read):
        # arrange
        mock_read.return_value = {"maintenance_date": "2026-05-28"}

        # act
        completed = maintenance_already_completed(
            "bucket", "key", region_name=TEST_REGION
        )

        # assert
        assert completed is True
        mock_read.assert_called_once_with("bucket", "key", region_name=TEST_REGION)

    @patch("bietlejuice.base.delta.maintenance_state.read_maintenance_marker")
    def test_false_when_marker_missing(self, mock_read):
        # arrange
        mock_read.return_value = None

        # act
        completed = maintenance_already_completed(
            "bucket", "key", region_name=TEST_REGION
        )

        # assert
        assert completed is False


class TestWriteMaintenanceMarker:
    @patch("bietlejuice.base.delta.maintenance_state.boto3")
    def test_puts_json_to_s3(self, mock_boto3):
        # arrange
        client = MagicMock()
        mock_boto3.client.return_value = client
        payload = build_maintenance_payload(
            full_table_name="datalake_dw.fact_x",
            maintenance_date="2026-05-28",
            environment="prod",
            dag_name="my_dag",
            run_vacuum=True,
            run_optimize=True,
        )

        # act
        write_maintenance_marker(
            "s3://artifacts-bucket",
            "path/to/marker.json",
            payload,
            region_name=TEST_REGION,
        )

        # assert
        mock_boto3.client.assert_called_once_with("s3", region_name=TEST_REGION)
        client.put_object.assert_called_once()
        call_kwargs = client.put_object.call_args[1]
        assert call_kwargs["Bucket"] == "artifacts-bucket"
        assert call_kwargs["Key"] == "path/to/marker.json"
        assert call_kwargs["ContentType"] == "application/json"
        assert json.loads(call_kwargs["Body"].decode("utf-8"))["dag_name"] == "my_dag"


class TestBuildMaintenancePayload:
    def test_includes_expected_fields(self):
        # act
        payload = build_maintenance_payload(
            full_table_name="datalake_dw.fact_x",
            maintenance_date="2026-05-28",
            environment="forno",
            dag_name="my_dag",
            run_vacuum=True,
            run_optimize=False,
        )

        # assert
        assert payload["full_table_name"] == "datalake_dw.fact_x"
        assert payload["maintenance_date"] == "2026-05-28"
        assert payload["environment"] == "forno"
        assert payload["dag_name"] == "my_dag"
        assert payload["run_vacuum"] is True
        assert payload["run_optimize"] is False
        assert "ts_completed" in payload


class TestResolveMarkerLocation:
    def test_returns_bucket_and_key(self):
        # arrange
        state_bucket = "s3://artifacts.example.com"
        environment = "forno"
        full_table_name = "datalake_clean.house"
        maintenance_date = "2026-05-28"

        # act
        bucket, key = resolve_marker_location(
            state_bucket=state_bucket,
            environment=environment,
            full_table_name=full_table_name,
            maintenance_date=maintenance_date,
            state_prefix=TEST_STATE_PREFIX,
        )

        # assert
        assert bucket == "artifacts.example.com"
        assert key.endswith("/2026-05-28.json")
        assert TEST_STATE_PREFIX in key


class TestBuildOptimizeCursorKey:
    def test_builds_non_date_keyed_path(self):
        # act
        key = build_optimize_cursor_key(
            environment="prod",
            full_table_name="datalake_dw_braze.fact_events",
            state_prefix=TEST_STATE_PREFIX,
        )

        # assert
        assert (
            key
            == "bi-etl-ejuice/delta_maintenance/prod/datalake_dw_braze__fact_events/optimize_cursor.json"
        )

    def test_strips_leading_and_trailing_slashes_from_prefix(self):
        # act
        key = build_optimize_cursor_key(
            environment="prod",
            full_table_name="db.table",
            state_prefix="/bi-etl-ejuice/delta_maintenance/",
        )

        # assert
        assert key.startswith("bi-etl-ejuice/delta_maintenance/prod/")
        assert key.endswith("/optimize_cursor.json")


class TestResolveOptimizeCursorLocation:
    def test_returns_bucket_and_key(self):
        # act
        bucket, key = resolve_optimize_cursor_location(
            state_bucket="s3://artifacts.example.com",
            environment="forno",
            full_table_name="datalake_clean.house",
            state_prefix=TEST_STATE_PREFIX,
        )

        # assert
        assert bucket == "artifacts.example.com"
        assert key.endswith("/optimize_cursor.json")
        assert TEST_STATE_PREFIX in key


class TestBuildOptimizeCursorPayload:
    def test_includes_expected_fields(self):
        # act
        payload = build_optimize_cursor_payload(
            full_table_name="datalake_dw.fact_x",
            last_optimize_date="2026-05-28",
            environment="forno",
            dag_name="my_dag",
        )

        # assert
        assert payload["full_table_name"] == "datalake_dw.fact_x"
        assert payload["last_optimize_date"] == "2026-05-28"
        assert payload["environment"] == "forno"
        assert payload["dag_name"] == "my_dag"
        assert "ts_completed" in payload


class TestParseIsoDate:
    def test_parses_valid_date(self):
        assert parse_iso_date("2026-05-28") == date(2026, 5, 28)

    def test_raises_on_invalid_format(self):
        with pytest.raises(ValueError):
            parse_iso_date("05/28/2026")


class TestDaysSinceLastOptimize:
    def test_none_when_no_cursor_payload(self):
        assert days_since_last_optimize(None, date(2026, 5, 28)) is None

    def test_none_when_payload_missing_date_field(self):
        assert days_since_last_optimize({}, date(2026, 5, 28)) is None

    def test_none_when_payload_date_is_malformed(self):
        payload = {"last_optimize_date": "not-a-date"}
        assert days_since_last_optimize(payload, date(2026, 5, 28)) is None

    def test_computes_elapsed_days(self):
        payload = {"last_optimize_date": "2026-05-21"}
        assert days_since_last_optimize(payload, date(2026, 5, 28)) == 7

    def test_zero_when_same_day(self):
        payload = {"last_optimize_date": "2026-05-28"}
        assert days_since_last_optimize(payload, date(2026, 5, 28)) == 0


class TestIsOptimizeDue:
    def test_always_due_when_frequency_is_daily_or_less(self):
        payload = {"last_optimize_date": "2026-05-28"}
        assert is_optimize_due(payload, date(2026, 5, 28), 1) is True
        assert is_optimize_due(payload, date(2026, 5, 28), 0) is True

    def test_due_on_cold_start_with_no_cursor(self):
        assert is_optimize_due(None, date(2026, 5, 28), 7) is True

    def test_not_due_before_frequency_elapses(self):
        payload = {"last_optimize_date": "2026-05-25"}
        assert is_optimize_due(payload, date(2026, 5, 28), 7) is False

    def test_due_once_frequency_elapses(self):
        payload = {"last_optimize_date": "2026-05-21"}
        assert is_optimize_due(payload, date(2026, 5, 28), 7) is True

    def test_due_when_frequency_elapsed_exactly(self):
        payload = {"last_optimize_date": "2026-05-21"}
        assert is_optimize_due(payload, date(2026, 5, 27), 7) is False
        assert is_optimize_due(payload, date(2026, 5, 28), 7) is True
