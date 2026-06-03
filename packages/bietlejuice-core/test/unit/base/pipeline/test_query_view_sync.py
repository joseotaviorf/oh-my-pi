import pytest

from bietlejuice.base.pipeline.query_view_sync import normalize_query_view_sync_config


class TestQueryViewSync:
    @pytest.mark.parametrize(
        "workflow_config, table_config, expected_sync, expected_sql_dialect",
        [
            ({}, None, ("databricks",), "databricks"),
            (
                {"sync": ["trino"], "sql_dialect": "trino"},
                None,
                ("trino",),
                "trino",
            ),
            (
                {"sync": ["trino", "databricks"], "sql_dialect": "trino"},
                None,
                ("databricks", "trino"),
                "trino",
            ),
            (
                {"sync": ["databricks"], "sql_dialect": "databricks"},
                {"sync": ["trino"], "sql_dialect": "trino"},
                ("trino",),
                "trino",
            ),
        ],
    )
    def test_normalize_query_view_sync_config(
        self,
        workflow_config,
        table_config,
        expected_sync,
        expected_sql_dialect,
    ):
        # act
        sync_config = normalize_query_view_sync_config(workflow_config, table_config)

        # assert
        assert sync_config.sync == expected_sync
        assert sync_config.sql_dialect == expected_sql_dialect

    @pytest.mark.parametrize(
        "workflow_config",
        [
            {"sync": []},
            {"sync": ["databricks", "databricks"]},
            {"sync": ["unknown"]},
            {"sql_dialect": "spark"},
            {"has_hive_sync": True},
            {"has_hive_sync": True, "sync": ["databricks"]},
        ],
    )
    def test_normalize_query_view_sync_config_rejects_invalid_config(
        self, workflow_config
    ):
        # act & assert
        with pytest.raises(ValueError):
            normalize_query_view_sync_config(workflow_config)
