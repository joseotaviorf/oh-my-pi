import pytest

from bietlejuice.base.pipeline.platform_resolver import (
    DataHubPlatform,
    resolve_has_hive_sync,
    resolve_platforms,
)

DATABRICKS = DataHubPlatform.DATABRICKS.value
GLUE = DataHubPlatform.GLUE.value
TRINO = DataHubPlatform.TRINO.value


class TestResolveHasHiveSync:
    def test_default_true_for_regular_workflow(self):
        assert resolve_has_hive_sync("enrich", {}, {}) is True

    def test_default_false_for_core_model(self):
        assert resolve_has_hive_sync("core_model", {}, {}) is False

    def test_workflow_level_overrides_type_default(self):
        assert resolve_has_hive_sync("enrich", {"has_hive_sync": False}, {}) is False
        assert resolve_has_hive_sync("core_model", {"has_hive_sync": True}, {}) is True

    def test_table_customization_overrides_workflow_level(self):
        assert (
            resolve_has_hive_sync(
                "enrich", {"has_hive_sync": False}, {"has_hive_sync": True}
            )
            is True
        )
        assert (
            resolve_has_hive_sync(
                "enrich", {"has_hive_sync": True}, {"has_hive_sync": False}
            )
            is False
        )


class TestResolvePlatforms:
    def test_regular_table_default_includes_trino(self):
        assert resolve_platforms("enrich", {}, {}) == [DATABRICKS, GLUE, TRINO]

    def test_core_model_default_excludes_trino(self):
        assert resolve_platforms("core_model", {}, {}) == [DATABRICKS, GLUE]

    def test_workflow_has_hive_sync_false_excludes_trino(self):
        assert resolve_platforms("enrich", {"has_hive_sync": False}, {}) == [
            DATABRICKS,
            GLUE,
        ]

    def test_table_customization_reenables_trino(self):
        platforms = resolve_platforms(
            "core_model", {"has_hive_sync": False}, {"has_hive_sync": True}
        )
        assert platforms == [DATABRICKS, GLUE, TRINO]

    def test_databricks_and_glue_always_present_for_tables(self):
        for wf in (
            "raw",
            "clean",
            "enrich",
            "dw",
            "qube_measure",
            "metric",
            "core_model",
        ):
            platforms = resolve_platforms(wf, {}, {})
            assert DATABRICKS in platforms
            assert GLUE in platforms

    def test_databricks_glue_trino_all_present_regardless_of_run_type(self):
        # platform set is a property of the FQN, not of the run (no is_validation
        # special-casing); DQ and description resolve the same way.
        assert resolve_platforms("enrich", {"has_hive_sync": True}, {}) == [
            DATABRICKS,
            GLUE,
            TRINO,
        ]


class TestResolvePlatformsQueryView:
    def test_default_sync_is_databricks_only(self):
        assert resolve_platforms("query_view", {}, {}) == [DATABRICKS]

    def test_sync_databricks_and_trino(self):
        assert resolve_platforms(
            "query_view", {"sync": ["databricks", "trino"]}, {}
        ) == [DATABRICKS, TRINO]

    def test_sync_trino_only(self):
        assert resolve_platforms("query_view", {"sync": ["trino"]}, {}) == [TRINO]

    def test_query_view_never_forces_glue(self):
        assert GLUE not in resolve_platforms(
            "query_view", {"sync": ["databricks", "trino"]}, {}
        )

    def test_table_customization_overrides_workflow_sync(self):
        assert resolve_platforms(
            "query_view", {"sync": ["databricks"]}, {"sync": ["trino"]}
        ) == [TRINO]

    def test_has_hive_sync_rejected_for_query_view(self):
        with pytest.raises(ValueError):
            resolve_platforms("query_view", {"has_hive_sync": True}, {})
