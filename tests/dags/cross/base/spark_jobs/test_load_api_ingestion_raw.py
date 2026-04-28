"""
Unit tests for _fetch_with_id_expansion and related helpers in load_api_ingestion_raw.

Tests cover the fan-out fetching strategy introduced by id_expansion: reading entity IDs
from a raw Spark table and making one API call per entity.
"""

import sys

import pytest
from unittest.mock import MagicMock, call

# Mock Spark/Databricks dependencies before importing the job module
sys.modules["quintoandar_logger"] = MagicMock()
sys.modules["pyspark"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.session"] = MagicMock()
sys.modules["pyspark.sql.functions"] = MagicMock()
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
    _fetch_with_id_expansion,
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
        )

        assert len(results) == 1
        assert results[0]["uuid"] == "holiday-a"
        assert results[0]["employeeUuid"] == "emp-1"
        client.get.assert_called_once_with(
            "holidays-groups/holidays/employees/emp-1",
            params={"from": "2026-01-01", "to": "2026-01-31"},
        )
