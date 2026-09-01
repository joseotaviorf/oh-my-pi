"""
Unit tests for _fetch_with_id_expansion and related helpers in load_api_ingestion_raw.

Tests cover the fan-out fetching strategy introduced by id_expansion: reading entity IDs
from a raw Spark table and making one API call per entity.
"""

import sys
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

from dags.cross.base.spark_jobs.load_api_ingestion_raw import (  # noqa: E402
    _date_expansion_param_names,
    _dates_last_n_days,
    _dates_previous_and_current_calendar_month,
    _fetch_plain_once,
    _fetch_with_id_expansion,
    _format_date_expansion_value,
    _resolve_date_expansion_values,
    _resolve_partitions,
)


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
            client, "punches", {"from": "2026-08-07", "to": "2026-08-07"}
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
