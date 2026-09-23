"""
Unit tests for _fetch_with_id_expansion and related helpers in load_api_ingestion_raw.

Tests cover the fan-out fetching strategy introduced by id_expansion: reading entity IDs
from a raw Spark table and making one API call per entity.
"""

import sys
from argparse import Namespace
from unittest.mock import MagicMock, call

import pytest

# Mock Spark/Databricks dependencies before importing the job module
sys.modules["quintoandar_logger"] = MagicMock()
sys.modules["pyspark"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.session"] = MagicMock()
sys.modules["pyspark.sql.functions"] = MagicMock()
sys.modules["pyspark.sql.window"] = MagicMock()
sys.modules["pyspark.sql.context"] = MagicMock()
sys.modules["pyspark.context"] = MagicMock()
sys.modules["bietlejuice.base.spark"] = MagicMock()
sys.modules["bietlejuice.base.spark.base_spark"] = MagicMock()
sys.modules["bietlejuice.base.spark.runtime_detector"] = MagicMock()
sys.modules["bietlejuice.clients.db_clients"] = MagicMock()
sys.modules["bietlejuice.jobs.common.helpers"] = MagicMock()
sys.modules["bietlejuice.jobs.common.raw_layer_loader"] = MagicMock()
sys.modules["bietlejuice.base.api.configuration.declaration_loader"] = MagicMock()
sys.modules["bietlejuice.base.api.configuration.loader"] = MagicMock()

import dags.cross.base.spark_jobs.load_api_ingestion_raw as api_job  # noqa: E402
from dags.cross.base.spark_jobs.load_api_ingestion_raw import (  # noqa: E402
    _date_expansion_param_names,
    _dates_last_n_days,
    _dates_load_window,
    _dates_previous_and_current_calendar_month,
    _fetch_plain_once,
    _fetch_plain_with_availability_tolerance,
    _fetch_with_id_expansion,
    _format_date_expansion_value,
    _resolve_availability_patterns,
    _resolve_date_expansion_values,
    _resolve_initial_params,
    _resolve_partitions,
)


class StubAPIError(Exception):
    """Minimal API exception with the fields used by availability handling."""

    def __init__(self, status_code, response_text):
        self.status_code = status_code
        self.response_text = response_text
        super().__init__(response_text)


class TestResolvePartitions:
    """Test suite for _resolve_partitions helper."""

    def test_empty_string_returns_default(self):
        assert _resolve_partitions("") == ["year", "month", "day"]

    def test_json_list_parsed_correctly(self):
        assert _resolve_partitions('["year", "month", "day"]') == [
            "year",
            "month",
            "day",
        ]

    def test_comma_separated_parsed_correctly(self):
        assert _resolve_partitions("year,month,day") == ["year", "month", "day"]

    def test_single_partition(self):
        assert _resolve_partitions("date") == ["date"]


class TestDateExpansionHelpers:
    """Tests for calendar date expansion helpers."""

    def test_previous_and_current_month_from_mid_july(self):
        dates = _dates_previous_and_current_calendar_month("2026-07-26")
        assert dates[0] == "2026-06-01"
        assert dates[-1] == "2026-07-26"
        assert len(dates) == 56

    def test_last_n_days_inclusive_window(self):
        dates = _dates_last_n_days("2026-07-26", 45)
        assert dates[0] == "2026-06-12"
        assert dates[-1] == "2026-07-26"
        assert len(dates) == 45

    def test_load_window_is_inclusive_across_month_boundary(self):
        # Arrange
        load_start_date = "2026-02-28"
        load_end_date = "2026-03-02"

        # Act
        dates = _resolve_date_expansion_values(
            {"strategy": "load_window"},
            load_start_date,
            load_end_date,
        )

        # Assert
        assert dates == ["2026-02-28", "2026-03-01", "2026-03-02"]

    def test_load_window_single_day_returns_one_date(self):
        # Arrange
        load_date = "2026-07-26"

        # Act
        dates = _dates_load_window(load_date, load_date)

        # Assert
        assert dates == [load_date]

    def test_load_window_reversed_dates_raise_clear_error(self):
        # Arrange
        load_start_date = "2026-07-27"
        load_end_date = "2026-07-26"

        # Act / Assert
        with pytest.raises(ValueError, match="load_start_date must be on or before"):
            _dates_load_window(load_start_date, load_end_date)

    def test_resolve_last_n_days_from_config(self):
        config = {
            "strategy": "last_n_days",
            "days": 45,
            "anchor": "load_end_date",
        }
        dates = _resolve_date_expansion_values(config, "2026-01-01", "2026-07-26")
        assert len(dates) == 45
        assert dates[-1] == "2026-07-26"

    def test_resolve_without_config_returns_single_none(self):
        assert _resolve_date_expansion_values(None, "2026-07-01", "2026-07-26") == [
            None
        ]

    def test_invalid_anchor_raises(self):
        with pytest.raises(ValueError, match="date_expansion.anchor"):
            _resolve_date_expansion_values(
                {
                    "strategy": "last_n_days",
                    "days": 2,
                    "anchor": "load_end",
                },
                "2026-01-01",
                "2026-07-26",
            )

    def test_format_date_expansion_respects_date_format(self):
        assert _format_date_expansion_value("2026-07-26", "%Y-%m-%d") == "2026-07-26"
        assert (
            _format_date_expansion_value("2026-07-26", None)
            == "2026-07-26T00:00:00.000Z"
        )
        assert _format_date_expansion_value("2026-09-21", "epoch_millis") == (
            1789948800000
        )


class TestDateParameterOffsets:
    """Tests for offsets applied after DAG conf date resolution."""

    def test_offset_uses_conf_resolved_date(self):
        # Arrange
        loader = MagicMock()
        loader.get_initial_params.return_value = {
            "from": "2026-08-10",
            "to": "load_end_date+1",
        }
        table_config = {
            "params": {
                "from": "load_start_date",
                "to": "load_end_date+1",
            }
        }

        # Act
        params = _resolve_initial_params(
            loader=loader,
            table_config=table_config,
            load_start_date="2026-08-10",
            load_end_date="2026-08-12",
            date_format="%Y-%m-%d",
        )

        # Assert
        assert params == {"from": "2026-08-10", "to": "2026-08-13"}
        loader.get_initial_params.assert_called_once_with("2026-08-10", "2026-08-12")

    def test_malformed_offset_raises_actionable_error(self):
        # Arrange
        invalid_value = "load_end_date+tomorrow"
        loader = MagicMock()
        loader.get_initial_params.return_value = {"date": invalid_value}
        table_config = {"params": {"date": invalid_value}}

        # Act / Assert
        with pytest.raises(ValueError, match="date offset"):
            _resolve_initial_params(
                loader=loader,
                table_config=table_config,
                load_start_date="2026-08-10",
                load_end_date="2026-08-12",
                date_format="%Y-%m-%d",
            )


class TestFetchWithIdExpansion:
    """Test suite for _fetch_with_id_expansion."""

    @staticmethod
    def _loader_without_pagination():
        """Loader whose create_paginator returns None (single GET per entity)."""
        loader = MagicMock()
        loader.create_paginator.return_value = None
        return loader

    def _make_spark(self, ids):
        """Builds a mock SparkSession that returns the given list of ID strings."""
        rows = []
        for id_value in ids:
            row = MagicMock()
            row.__getitem__ = MagicMock(return_value=id_value)
            rows.append(row)

        df_mock = MagicMock()
        df_mock.select.return_value = df_mock
        df_mock.where.return_value = df_mock
        df_mock.withColumn.return_value = df_mock
        df_mock.distinct.return_value = df_mock
        df_mock.collect.return_value = rows

        spark = MagicMock()
        spark.table.return_value = df_mock
        return spark

    def _make_response(self, data):
        resp = MagicMock()
        resp.json.return_value = data
        return resp

    def test_single_dict_response_enriched_with_id(self):
        """Each single-object response gets the entity id_field injected."""
        spark = self._make_spark(["uuid-1", "uuid-2"])
        client = MagicMock()
        client.get.side_effect = [
            self._make_response({"date": "2026-04-12", "totals": {"negative": -60}}),
            self._make_response({"date": "2026-04-12", "totals": {}}),
        ]

        results = _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=self._loader_without_pagination(),
            id_expansion_config={
                "source_table": "employees",
                "id_field": "uuid",
                "param_name": "employeeUuid",
            },
            source_schema="oitchau",
            endpoint="employees/hoursbank/totals",
            initial_params={"date": "2026-04-12"},
            load_start_date="2026-04-12",
            load_end_date="2026-04-12",
        )

        assert len(results) == 2
        assert results[0]["uuid"] == "uuid-1"
        assert results[0]["totals"] == {"negative": -60}
        assert results[1]["uuid"] == "uuid-2"

    def test_list_response_items_enriched_with_id(self):
        """List API responses expand into multiple items, each with id_field injected."""
        spark = self._make_spark(["emp-1"])
        client = MagicMock()
        client.get.return_value = self._make_response(
            [{"requestUuid": "r1"}, {"requestUuid": "r2"}]
        )

        results = _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=self._loader_without_pagination(),
            id_expansion_config={
                "source_table": "employees",
                "id_field": "uuid",
                "param_name": "employeeUuid",
            },
            source_schema="oitchau",
            endpoint="requests/employees/emp-1",
            initial_params={},
            load_start_date="2026-04-12",
            load_end_date="2026-04-12",
        )

        assert len(results) == 2
        assert results[0]["uuid"] == "emp-1"
        assert results[1]["uuid"] == "emp-1"

    def test_failed_entity_is_skipped_and_logged(self):
        """A failing API call for one entity is logged as warning and skipped."""
        spark = self._make_spark(["uuid-ok", "uuid-fail"])
        client = MagicMock()
        client.get.side_effect = [
            self._make_response({"date": "2026-04-12", "totals": {}}),
            Exception("HTTP 500"),
        ]

        results = _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=self._loader_without_pagination(),
            id_expansion_config={
                "source_table": "employees",
                "id_field": "uuid",
                "param_name": "employeeUuid",
            },
            source_schema="oitchau",
            endpoint="employees/hoursbank/totals",
            initial_params={"date": "2026-04-12"},
            load_start_date="2026-04-12",
            load_end_date="2026-04-12",
        )

        assert len(results) == 1
        assert results[0]["uuid"] == "uuid-ok"

    def test_correct_source_table_path_used(self):
        """Spark reads from the correct fully-qualified raw table name."""
        spark = self._make_spark([])
        client = MagicMock()

        _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=self._loader_without_pagination(),
            id_expansion_config={
                "source_table": "employees",
                "id_field": "uuid",
                "param_name": "employeeUuid",
            },
            source_schema="oitchau",
            endpoint="employees/hoursbank/totals",
            initial_params={},
            load_start_date="2026-04-12",
            load_end_date="2026-04-12",
        )

        spark.table.assert_called_once_with("datalake_oitchau_raw.employees")

    def test_param_name_injected_into_each_request(self):
        """employeeUuid is appended as a query param on each per-entity GET call."""
        spark = self._make_spark(["uuid-a", "uuid-b"])
        client = MagicMock()
        client.get.return_value = self._make_response(
            {"date": "2026-04-12", "totals": {}}
        )

        _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=self._loader_without_pagination(),
            id_expansion_config={
                "source_table": "employees",
                "id_field": "uuid",
                "param_name": "employeeUuid",
            },
            source_schema="oitchau",
            endpoint="employees/hoursbank/totals",
            initial_params={"date": "2026-04-12"},
            load_start_date="2026-04-12",
            load_end_date="2026-04-12",
        )

        assert client.get.call_count == 2
        assert client.get.call_args_list[0] == call(
            "employees/hoursbank/totals",
            params={"date": "2026-04-12", "employeeUuid": "uuid-a"},
        )
        assert client.get.call_args_list[1] == call(
            "employees/hoursbank/totals",
            params={"date": "2026-04-12", "employeeUuid": "uuid-b"},
        )

    def test_path_param_substitutes_placeholder_in_url(self):
        """path_param replaces {placeholder} in endpoint; ID is not sent as a query param."""
        spark = self._make_spark(["emp-uuid-1"])
        client = MagicMock()
        client.get.return_value = self._make_response(
            {"content": [{"uuid": "r1"}], "metadata": {"totalPages": 1}}
        )

        _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=self._loader_without_pagination(),
            id_expansion_config={
                "source_table": "employees",
                "id_field": "uuid",
                "path_param": "employeeUuid",
            },
            source_schema="oitchau",
            endpoint="requests/employees/{employeeUuid}",
            initial_params={"from": "2025-01-01", "to": "2026-01-01"},
            load_start_date="2025-01-01",
            load_end_date="2026-01-01",
        )

        client.get.assert_called_once_with(
            "requests/employees/emp-uuid-1",
            params={"from": "2025-01-01", "to": "2026-01-01"},
        )

    def test_id_expansion_with_paginator_flattens_all_pages(self):
        """When create_paginator returns a paginator, all yielded rows get id_field and no bare GET."""
        spark = self._make_spark(["emp-1"])
        client = MagicMock()
        paginator = MagicMock()
        paginator.fetch_all.return_value = iter(
            [
                [{"requestUuid": "a"}],
                [{"requestUuid": "b"}],
            ]
        )
        loader = MagicMock()
        loader.create_paginator.return_value = paginator

        results = _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=loader,
            id_expansion_config={
                "source_table": "employees",
                "id_field": "uuid",
                "path_param": "employeeUuid",
            },
            source_schema="oitchau",
            endpoint="requests/employees/{employeeUuid}",
            initial_params={"from": "2025-01-01", "to": "2026-01-01"},
            load_start_date="2025-01-01",
            load_end_date="2026-01-01",
        )

        assert len(results) == 2
        assert results[0]["uuid"] == "emp-1"
        assert results[1]["uuid"] == "emp-1"
        client.get.assert_not_called()
        loader.create_paginator.assert_called_once()

    def test_both_path_param_and_param_name_raises(self):
        """Setting more than one fan-out mode (path_param, param_name, json_body_field) is rejected."""
        spark = self._make_spark(["x"])
        client = MagicMock()

        with pytest.raises(ValueError, match="exactly one of"):
            _fetch_with_id_expansion(
                spark=spark,
                client=client,
                loader=self._loader_without_pagination(),
                id_expansion_config={
                    "source_table": "employees",
                    "id_field": "uuid",
                    "path_param": "employeeUuid",
                    "param_name": "employeeUuid",
                },
                source_schema="oitchau",
                endpoint="requests/employees/{employeeUuid}",
                initial_params={},
                load_start_date="2026-04-12",
                load_end_date="2026-04-12",
            )

    def test_json_body_field_post_flattens_content_array(self):
        """POST fan-out with json_body_field expands content[] and stamps correlation_field."""
        spark = self._make_spark(["136116"])
        client = MagicMock()
        client.post.return_value = self._make_response(
            {
                "content": [
                    {
                        "uuid": "row-1",
                        "rate": 45.45,
                        "userProfileUuid": "prof-1",
                    }
                ]
            }
        )

        results = _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=self._loader_without_pagination(),
            id_expansion_config={
                "source_table": "employees",
                "id_field": "externalId",
                "correlation_field": "employeeExternalId",
                "json_body_field": "employeeExternalId",
            },
            source_schema="oitchau",
            endpoint="costs/list",
            initial_params={},
            load_start_date="2026-04-12",
            load_end_date="2026-04-12",
        )

        assert len(results) == 1
        assert results[0]["uuid"] == "row-1"
        assert results[0]["employeeExternalId"] == "136116"
        client.post.assert_called_once_with(
            "costs/list",
            params={},
            json={"employeeExternalId": "136116"},
        )

    def test_json_body_field_with_pagination_raises(self):
        """json_body_field fan-out rejects pagination (GET-only paginators)."""
        spark = self._make_spark(["1"])
        client = MagicMock()
        loader = MagicMock()
        loader.create_paginator.return_value = MagicMock()

        with pytest.raises(ValueError, match="json_body_field"):
            _fetch_with_id_expansion(
                spark=spark,
                client=client,
                loader=loader,
                id_expansion_config={
                    "source_table": "employees",
                    "id_field": "externalId",
                    "json_body_field": "employeeExternalId",
                },
                source_schema="oitchau",
                endpoint="costs/list",
                initial_params={},
                load_start_date="2026-04-12",
                load_end_date="2026-04-12",
            )

    def test_empty_source_table_returns_empty_list(self):
        """When the source table has no IDs, an empty list is returned without API calls."""
        spark = self._make_spark([])
        client = MagicMock()

        results = _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=self._loader_without_pagination(),
            id_expansion_config={
                "source_table": "employees",
                "id_field": "uuid",
                "param_name": "employeeUuid",
            },
            source_schema="oitchau",
            endpoint="employees/hoursbank/totals",
            initial_params={"date": "2026-04-12"},
            load_start_date="2026-04-12",
            load_end_date="2026-04-12",
        )

        assert results == []
        client.get.assert_not_called()

    def test_id_expansion_correlation_field_on_list_response(self):
        """List bodies are stamped with correlation_field when set, preserving native uuid."""
        spark = self._make_spark(["emp-1"])
        client = MagicMock()
        response = MagicMock()
        response.json.return_value = [{"uuid": "holiday-a", "name": "Xmas"}]
        client.get.return_value = response
        loader = self._loader_without_pagination()

        results = _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=loader,
            id_expansion_config={
                "source_table": "employees",
                "id_field": "uuid",
                "correlation_field": "employeeUuid",
                "path_param": "employeeUuid",
            },
            source_schema="oitchau",
            endpoint="holidays-groups/holidays/employees/{employeeUuid}",
            initial_params={"from": "2026-01-01", "to": "2026-01-31"},
            load_start_date="2026-01-01",
            load_end_date="2026-01-31",
        )

        assert len(results) == 1
        assert results[0]["uuid"] == "holiday-a"
        assert results[0]["employeeUuid"] == "emp-1"
        client.get.assert_called_once_with(
            "holidays-groups/holidays/employees/emp-1",
            params={"from": "2026-01-01", "to": "2026-01-31"},
        )

    def test_payload_filters_missing_equals_raises(self):
        """A payload_filters entry without equals fails fast instead of silently skipping."""
        spark = self._make_spark(["uuid-1"])
        client = MagicMock()

        with pytest.raises(ValueError, match="requires 'equals'"):
            _fetch_with_id_expansion(
                spark=spark,
                client=client,
                loader=self._loader_without_pagination(),
                id_expansion_config={
                    "source_table": "employees",
                    "id_field": "uuid",
                    "param_name": "employeeUuid",
                    "payload_filters": [{"field": "active"}],
                },
                source_schema="oitchau",
                endpoint="employees/hoursbank/totals",
                initial_params={},
                load_start_date="2026-04-12",
                load_end_date="2026-04-12",
            )

    def test_payload_filters_single_dict_is_accepted(self):
        """A bare YAML map under payload_filters is normalized to a one-element list."""
        spark = self._make_spark(["uuid-1"])
        client = MagicMock()
        client.get.return_value = self._make_response(
            {"date": "2026-04-12", "totals": {}}
        )

        results = _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=self._loader_without_pagination(),
            id_expansion_config={
                "source_table": "employees",
                "id_field": "uuid",
                "param_name": "employeeUuid",
                "payload_filters": {"field": "active", "equals": True},
            },
            source_schema="oitchau",
            endpoint="employees/hoursbank/totals",
            initial_params={"date": "2026-04-12"},
            load_start_date="2026-04-12",
            load_end_date="2026-04-12",
        )

        assert len(results) == 1
        assert results[0]["uuid"] == "uuid-1"

    def test_path_param_missing_placeholder_fails_before_fan_out(self):
        """Bad endpoint_path / path_param pairs fail before per-entity tasks run."""
        spark = self._make_spark(["emp-1"])
        client = MagicMock()

        with pytest.raises(ValueError, match="endpoint_path must contain"):
            _fetch_with_id_expansion(
                spark=spark,
                client=client,
                loader=self._loader_without_pagination(),
                id_expansion_config={
                    "source_table": "employees",
                    "id_field": "uuid",
                    "path_param": "employeeUuid",
                },
                source_schema="oitchau",
                endpoint="requests/employees/missing-placeholder",
                initial_params={},
                load_start_date="2026-04-12",
                load_end_date="2026-04-12",
            )

        client.get.assert_not_called()

    def test_date_expansion_without_param_name_raises(self):
        """date_expansion with multiple dates requires param_name to vary the query."""
        spark = self._make_spark(["uuid-1"])
        client = MagicMock()

        with pytest.raises(ValueError, match="date_expansion.param_name"):
            _fetch_with_id_expansion(
                spark=spark,
                client=client,
                loader=self._loader_without_pagination(),
                id_expansion_config={
                    "source_table": "employees",
                    "id_field": "uuid",
                    "param_name": "employeeUuid",
                },
                source_schema="oitchau",
                endpoint="employees/hoursbank/totals",
                initial_params={},
                load_start_date="2026-04-12",
                load_end_date="2026-04-12",
                date_expansion_config={
                    "strategy": "last_n_days",
                    "days": 2,
                    "anchor": "load_end_date",
                },
            )

    def test_load_window_uses_date_format_for_each_id_request(self):
        # Arrange
        spark = self._make_spark(["uuid-1"])
        client = MagicMock()
        client.get.side_effect = [
            self._make_response({"date": "2026-07-01"}),
            self._make_response({"date": "2026-07-02"}),
            self._make_response({"date": "2026-07-03"}),
        ]

        # Act
        results = _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=self._loader_without_pagination(),
            id_expansion_config={
                "source_table": "employees",
                "id_field": "uuid",
                "param_name": "employeeUuid",
            },
            source_schema="oitchau",
            endpoint="employees/hoursbank/totals",
            initial_params={},
            load_start_date="2026-07-01",
            load_end_date="2026-07-03",
            date_expansion_config={
                "strategy": "load_window",
                "param_name": "date",
            },
            date_format="%d/%m/%Y",
        )

        # Assert
        assert len(results) == 3
        assert client.get.call_args_list == [
            call(
                "employees/hoursbank/totals",
                params={"date": "01/07/2026", "employeeUuid": "uuid-1"},
            ),
            call(
                "employees/hoursbank/totals",
                params={"date": "02/07/2026", "employeeUuid": "uuid-1"},
            ),
            call(
                "employees/hoursbank/totals",
                params={"date": "03/07/2026", "employeeUuid": "uuid-1"},
            ),
        ]

    def test_max_workers_zero_raises(self):
        """YAML max_workers: 0 must raise instead of silently becoming sequential."""
        spark = self._make_spark(["uuid-1"])
        client = MagicMock()

        with pytest.raises(ValueError, match="max_workers must be >= 1"):
            _fetch_with_id_expansion(
                spark=spark,
                client=client,
                loader=self._loader_without_pagination(),
                id_expansion_config={
                    "source_table": "employees",
                    "id_field": "uuid",
                    "param_name": "employeeUuid",
                    "max_workers": 0,
                },
                source_schema="oitchau",
                endpoint="employees/hoursbank/totals",
                initial_params={},
                load_start_date="2026-04-12",
                load_end_date="2026-04-12",
            )


class TestDateExpansionParamNames:
    """Tests for _date_expansion_param_names."""

    def test_single_param_name(self):
        assert _date_expansion_param_names({"param_name": "date"}) == ["date"]

    def test_param_names_list(self):
        assert _date_expansion_param_names({"param_names": ["from", "to"]}) == [
            "from",
            "to",
        ]

    def test_param_names_wins_over_param_name(self):
        config = {"param_name": "date", "param_names": ["from", "to"]}
        assert _date_expansion_param_names(config) == ["from", "to"]

    def test_missing_both_raises(self):
        with pytest.raises(ValueError, match="date_expansion.param_name"):
            _date_expansion_param_names({"strategy": "last_n_days"})

    def test_empty_param_names_raises(self):
        with pytest.raises(ValueError, match="param_names"):
            _date_expansion_param_names({"param_names": []})

    def test_non_string_param_names_raises(self):
        with pytest.raises(ValueError, match="param_names"):
            _date_expansion_param_names({"param_names": ["from", 2]})


class TestFetchPlainOnce:
    """Tests for the plain (non-id_expansion) fetch helper."""

    @staticmethod
    def _loader_with_pages(pages):
        loader = MagicMock()
        paginator = MagicMock()
        paginator.fetch_all.return_value = iter(pages)
        loader.create_paginator.return_value = paginator
        return loader

    def test_paginated_fetch_concatenates_pages(self):
        loader = self._loader_with_pages([[{"id": 1}], [{"id": 2}, {"id": 3}]])
        client = MagicMock()

        rows = _fetch_plain_once(
            client=client,
            loader=loader,
            table_config={},
            table_name="punches",
            endpoint="punches",
            params={"from": "2026-08-07", "to": "2026-08-07"},
        )

        assert [row["id"] for row in rows] == [1, 2, 3]
        loader.create_paginator.assert_called_once_with(
            client,
            "punches",
            {"from": "2026-08-07", "to": "2026-08-07"},
            json_body=None,
        )
        client.get.assert_not_called()

    def test_paginated_fetch_passes_json_body_to_paginator(self):
        loader = self._loader_with_pages([[{"id": 1}]])
        client = MagicMock()
        body = {"startDate": 1789948800000, "endDate": 1790035199999}

        _fetch_plain_once(
            client=client,
            loader=loader,
            table_config={},
            table_name="daily_usage",
            endpoint="teams/daily-usage-data",
            params={},
            json_body=body,
        )

        loader.create_paginator.assert_called_once_with(
            client, "teams/daily-usage-data", {}, json_body=body
        )

    def test_single_page_post_sends_json_body(self):
        loader = MagicMock()
        loader.create_paginator.return_value = None
        loader.get_http_method.return_value = "post"
        client = MagicMock()
        client.post.return_value.json.return_value = {"items": [{"id": 9}]}

        rows = _fetch_plain_once(
            client=client,
            loader=loader,
            table_config={"results_response_path": "items"},
            table_name="events",
            endpoint="events",
            params={},
            json_body={"startDate": 1789948800000},
        )

        assert rows == [{"id": 9}]
        client.post.assert_called_once_with(
            "events", params={}, json={"startDate": 1789948800000}
        )
        client.get.assert_not_called()

    def test_single_page_uses_results_response_path(self):
        loader = MagicMock()
        loader.create_paginator.return_value = None
        client = MagicMock()
        client.get.return_value.json.return_value = {"items": [{"id": 9}]}

        rows = _fetch_plain_once(
            client=client,
            loader=loader,
            table_config={"results_response_path": "items"},
            table_name="events",
            endpoint="events",
            params={},
        )

        assert rows == [{"id": 9}]
        client.get.assert_called_once_with("events", params={})

    def test_single_page_list_response(self):
        loader = MagicMock()
        loader.create_paginator.return_value = None
        client = MagicMock()
        client.get.return_value.json.return_value = [{"id": 1}]

        rows = _fetch_plain_once(
            client=client,
            loader=loader,
            table_config={},
            table_name="events",
            endpoint="events",
            params={},
        )

        assert rows == [{"id": 1}]


class TestAvailabilityTolerance:
    """Tests for opt-in unavailable-date handling."""

    def test_message_patterns_are_required(self):
        # Arrange
        table_config = {"availability_tolerance": {"message_patterns": []}}

        # Act / Assert
        with pytest.raises(ValueError, match="message_patterns"):
            _resolve_availability_patterns(table_config)

    @staticmethod
    def _loader_without_pagination():
        loader = MagicMock()
        loader.create_paginator.return_value = None
        return loader

    @staticmethod
    def _response(data):
        response = MagicMock()
        response.json.return_value = data
        return response

    def test_matching_400_is_skipped(self):
        # Arrange
        loader = self._loader_without_pagination()
        client = MagicMock()
        client.get.side_effect = StubAPIError(400, "Latest AVAILABLE data is yesterday")

        # Act
        rows = _fetch_plain_with_availability_tolerance(
            client=client,
            loader=loader,
            table_config={},
            table_name="summaries",
            endpoint="summaries",
            params={"ending_date": "2026-08-13"},
            availability_patterns=["latest available data"],
            date_value="2026-08-12",
        )

        # Assert
        assert rows == []
        client.get.assert_called_once_with(
            "summaries", params={"ending_date": "2026-08-13"}
        )

    @pytest.mark.parametrize(
        ("status_code", "message"),
        [
            (400, "Invalid ending_date"),
            (500, "Latest available data is yesterday"),
        ],
    )
    def test_non_matching_status_or_message_propagates(self, status_code, message):
        # Arrange
        loader = self._loader_without_pagination()
        client = MagicMock()
        error = StubAPIError(status_code, message)
        client.get.side_effect = error

        # Act / Assert
        with pytest.raises(StubAPIError) as raised:
            _fetch_plain_with_availability_tolerance(
                client=client,
                loader=loader,
                table_config={},
                table_name="summaries",
                endpoint="summaries",
                params={},
                availability_patterns=["latest available data"],
            )
        assert raised.value is error

    def test_shifted_date_fallback_succeeds_with_unshifted_params(self):
        # Arrange
        loader = self._loader_without_pagination()
        client = MagicMock()
        client.get.side_effect = [
            StubAPIError(400, "Latest available data is yesterday"),
            self._response({"results": [{"id": 1}]}),
        ]

        # Act
        rows = _fetch_plain_with_availability_tolerance(
            client=client,
            loader=loader,
            table_config={},
            table_name="summaries",
            endpoint="summaries",
            params={"ending_date": "2026-08-13"},
            fallback_params={"ending_date": "2026-08-12"},
            availability_patterns=["latest available data"],
        )

        # Assert
        assert rows == [{"id": 1}]
        assert client.get.call_args_list == [
            call("summaries", params={"ending_date": "2026-08-13"}),
            call("summaries", params={"ending_date": "2026-08-12"}),
        ]

    def test_matching_fallback_error_is_skipped(self):
        # Arrange
        loader = self._loader_without_pagination()
        client = MagicMock()
        client.get.side_effect = [
            StubAPIError(400, "Latest available data is yesterday"),
            StubAPIError(400, "Latest available data is yesterday"),
        ]

        # Act
        rows = _fetch_plain_with_availability_tolerance(
            client=client,
            loader=loader,
            table_config={},
            table_name="summaries",
            endpoint="summaries",
            params={"ending_date": "2026-08-13"},
            fallback_params={"ending_date": "2026-08-12"},
            availability_patterns=["latest available data"],
        )

        # Assert
        assert rows == []
        assert client.get.call_count == 2

    def test_id_expansion_fallback_uses_unshifted_params(self):
        # Arrange
        spark = TestFetchWithIdExpansion()._make_spark(["uuid-1"])
        client = MagicMock()
        client.get.side_effect = [
            StubAPIError(400, "Latest available data is yesterday"),
            self._response({"date": "2026-08-12"}),
        ]

        # Act
        rows = _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=TestFetchWithIdExpansion._loader_without_pagination(),
            id_expansion_config={
                "source_table": "employees",
                "id_field": "uuid",
                "param_name": "employeeUuid",
            },
            source_schema="oitchau",
            endpoint="summaries",
            initial_params={"ending_date": "2026-08-13"},
            fallback_params={"ending_date": "2026-08-12"},
            load_start_date="2026-08-12",
            load_end_date="2026-08-13",
            availability_patterns=["latest available data"],
        )

        # Assert
        assert len(rows) == 1
        assert client.get.call_args_list == [
            call(
                "summaries",
                params={
                    "ending_date": "2026-08-13",
                    "employeeUuid": "uuid-1",
                },
            ),
            call(
                "summaries",
                params={
                    "ending_date": "2026-08-12",
                    "employeeUuid": "uuid-1",
                },
            ),
        ]


class TestMainValidationTargetRouting:
    """Tests that main forwards validation targets to the raw loader."""

    @pytest.fixture
    def main_dependencies(self, monkeypatch):
        args = Namespace(
            environment="forno",
            datalake_bucket="test-bucket",
            dag_name="dag_api_raw",
            table_name="events",
            execution_date="2026-08-13",
            partitions='["year", "month", "day"]',
            extraction_type="incremental",
            load_start_date="2026-08-12",
            load_end_date="2026-08-13",
            target_database_name=None,
            target_table_name=None,
        )
        loader = MagicMock()
        loader.get_endpoint_path.return_value = "events"
        loader.get_payload_column_name.return_value = "payload"
        loader.get_date_column_for_partitioning.return_value = None
        loader.get_id_expansion_config.return_value = None
        loader.get_initial_params.return_value = {}
        loader.create_paginator.return_value = None
        loader.create_api_client.return_value.get.return_value = {
            "results": [{"id": 1}]
        }
        raw_loader = MagicMock()
        spark_client = MagicMock()
        spark_client_factory = MagicMock(return_value=spark_client)

        monkeypatch.setattr(api_job, "parse_arguments", lambda: args)
        monkeypatch.setattr(
            api_job,
            "validate_api_ingestion_dag_name",
            lambda dag_name: dag_name,
        )
        monkeypatch.setattr(
            api_job,
            "load_api_ingestion_declaration",
            lambda _: {
                "workflow": {
                    "type": "api_ingestion",
                    "custom_schema": "api_raw",
                    "tables_customization": {
                        "events": {"endpoint_path": "events", "params": {}}
                    },
                }
            },
        )
        monkeypatch.setattr(
            api_job, "APIConfigurationLoader", MagicMock(return_value=loader)
        )
        monkeypatch.setattr(api_job, "RawLayerLoader", raw_loader)
        monkeypatch.setattr(api_job, "SparkClient", spark_client_factory)
        monkeypatch.setattr(
            api_job, "_initialize_spark", MagicMock(return_value=MagicMock())
        )
        monkeypatch.setattr(
            api_job, "json_to_dataframe", MagicMock(return_value=MagicMock())
        )
        monkeypatch.setattr(
            api_job, "insert_partitions", MagicMock(return_value=MagicMock())
        )
        return args, loader, raw_loader, spark_client

    @pytest.mark.parametrize(
        ("target_database_name", "target_table_name"),
        [
            ("cluster_validation", "datalake_api_raw___events"),
            (None, None),
        ],
    )
    def test_main_forwards_target_arguments(
        self,
        main_dependencies,
        target_database_name,
        target_table_name,
    ):
        # Arrange
        args, loader, raw_loader, spark_client = main_dependencies
        args.target_database_name = target_database_name
        args.target_table_name = target_table_name

        # Act
        api_job.main()

        # Assert
        raw_loader.assert_called_once_with(
            spark_client=spark_client,
            environment="forno",
            source="api_raw",
            datalake_bucket="test-bucket",
            table_name="events",
            partition_cols=["year", "month", "day"],
            extraction_type="incremental",
            target_database_name=target_database_name,
            target_table_name=target_table_name,
        )
