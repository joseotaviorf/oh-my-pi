import re

import pytest

from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags import COMPOSER_DAGS_PATH
from bietlejuice.jobs.composer.services.dag_metadata_service import DAGMetadataService


class TestDAGMetadataService:
    @pytest.mark.parametrize(
        "dag_manual_mapping", (None, {"test_dag": {"layer": {"database_name": "db"}}})
    )
    def test__init__(self, dag_manual_mapping):
        # act
        service = DAGMetadataService(dag_manual_mapping=dag_manual_mapping)

        # assert
        assert service._STAGING_LAYERS == {
            LayerEnum.DW_STAGING.value,
            LayerEnum.CLEAN_STAGING.value,
        }
        assert service._DAG_PATH_REGEX == re.compile(
            r"dags/(?P<source>\w+)(?:/(?P<context>\w+))?/(?P<dag>\w+)\.py"
        )
        assert service._DAG_OWNER_REGEX == re.compile('"owner": ([\w.]*)[,|\n]?')
        assert service._RAW_LAYER_MATCH_REGEX == re.compile(
            "build_raw_task_group_for_all_tables|build_raw_task_group_for_single_table|sync-hive-metastore-raw"
        )
        assert service._CLEAN_LAYER_MATCH_REGEX == re.compile(
            "sync-hive-metastore-clean|build_clean_task_group"
        )
        assert service._BUILD_TASK_GROUP_LAYER_REGEX == re.compile(
            r"build_task_group_from_sql_files.*?layer ?= ?LayerEnum\.(\w+)",
            flags=re.DOTALL,
        )
        assert service._SYNC_METASTORE_PARAMETERS == re.compile(
            r"sync_metastore_tables_structure\.py.*?\"parameters\": ?\[(.*?)]",
            flags=re.DOTALL,
        )
        assert service._GENERIC_TARGET_DATABASE_NAME == re.compile(
            r"target_database_base_name ?= ?(\w+)"
        )
        assert service._DW_TASK_GROUP_SCHEMA == re.compile(
            r"DWTaskGroup.*?dw_schema ?= ?(\w*)", flags=re.DOTALL
        )

    @pytest.mark.parametrize(
        "source, context, expected_intermediate_path",
        [
            ("dag_source", "dag_source", None),
            ("dag_source", "dag_context", f"dag_source/dag_context"),
        ],
    )
    def test__get_intermediate_path(self, source, context, expected_intermediate_path):
        # arrange
        service = DAGMetadataService()

        # act
        result = service._get_intermediate_path(source, context)

        # assert
        assert result == expected_intermediate_path

    @pytest.mark.parametrize(
        "source, context, dag_name, intermediate_path, expected_path",
        [
            (
                "dag_source",
                "dag_source",
                "dag_name",
                None,
                f"{COMPOSER_DAGS_PATH}/dag_source/dag_name.py",
            ),
            (
                "dag_source",
                "dag_context",
                "dag_name",
                "dag_source/dag_context",
                f"{COMPOSER_DAGS_PATH}/dag_source/dag_context/dag_name.py",
            ),
        ],
    )
    def test__get_dag_file_path(
        self,
        source: str,
        context: str,
        dag_name: str,
        intermediate_path: str,
        expected_path: str,
    ):
        # arrange
        service = DAGMetadataService()

        # act
        result = service._get_dag_file_path(source, context, dag_name)

        # assert
        assert result == expected_path
