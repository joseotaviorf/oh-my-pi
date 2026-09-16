import pytest

from bietlejuice.governance.layer_taxonomy_pilot import (
    PILOT_DAG_NAMES,
    PILOT_DAG_PATH_PREFIXES,
    is_pilot_dag,
    is_pilot_dag_path,
)


class TestPilotDagRegistry:
    def test_holds_exactly_the_four_pilot_dags(self):
        # assert — pinned so teardown is visible in the diff
        assert PILOT_DAG_NAMES == frozenset(
            {
                "transformation_terminator_test",
                "transformation_offboarding_test",
                "transformation_hefesto_test",
                "consumption_offboarding_test",
            }
        )

    def test_every_name_has_a_matching_path_prefix(self):
        # assert
        assert len(PILOT_DAG_PATH_PREFIXES) == len(PILOT_DAG_NAMES)
        for name in PILOT_DAG_NAMES:
            assert f"dags/governance/{name}/" in PILOT_DAG_PATH_PREFIXES

    def test_prefixes_end_with_a_slash(self):
        """Without it, a longer sibling folder would match by prefix."""
        # assert
        assert all(prefix.endswith("/") for prefix in PILOT_DAG_PATH_PREFIXES)


class TestIsPilotDag:
    @pytest.mark.parametrize("dag_name", sorted(PILOT_DAG_NAMES))
    def test_matches_each_pilot_dag(self, dag_name):
        assert is_pilot_dag(dag_name) is True

    @pytest.mark.parametrize(
        "dag_name",
        [
            "enrich_terminator",
            "enrich_offboarding",
            "dw_offboarding",
            "glue_table_version_cleanup",
            # Substring and near-miss names must not match.
            "transformation_terminator",
            "transformation_terminator_test_v2",
            "",
        ],
    )
    def test_rejects_non_pilot_dags(self, dag_name):
        assert is_pilot_dag(dag_name) is False


class TestIsPilotDagPath:
    @pytest.mark.parametrize(
        "path",
        [
            "dags/governance/transformation_terminator_test/queries/transformation/x.sql",
            "dags/governance/consumption_offboarding_test/consumption_offboarding_test_declaration.yml",
            "dags/governance/transformation_hefesto_test/metadata/transformation/y.yml",
        ],
    )
    def test_matches_files_inside_pilot_folders(self, path):
        assert is_pilot_dag_path(path) is True

    @pytest.mark.parametrize(
        "path",
        [
            # Real governance DAGs must keep their governance coverage.
            "dags/governance/glue_table_version_cleanup/queries/enrich/x.sql",
            "dags/for_rent/enrich_terminator/queries/enrich/x.sql",
            "dags/platform/migration_emr_foo/queries/enrich/x.sql",
            # A longer folder that merely starts with a pilot name.
            "dags/governance/transformation_terminator_test_v2/queries/enrich/x.sql",
            # Same name outside the governance domain.
            "dags/for_rent/transformation_terminator_test/queries/enrich/x.sql",
            "",
        ],
    )
    def test_rejects_paths_outside_pilot_folders(self, path):
        assert is_pilot_dag_path(path) is False
