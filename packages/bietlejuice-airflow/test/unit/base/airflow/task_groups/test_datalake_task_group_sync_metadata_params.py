"""Unit tests for DatalakeTaskGroup sync_metadata parameter assembly."""

from unittest import mock

from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum


class TestDatalakeTaskGroupSyncMetadataParams:
    def _task_group(self, **kwargs):
        with mock.patch(
            "bietlejuice.base.airflow.task_groups.datalake_task_group.ConfigurationService"
        ) as mock_config_svc:
            mock_config_svc.return_value.get_config.return_value = "mock_bucket"
            mock_config_svc.return_value.configs = {}
            group = DatalakeTaskGroup(
                dag=mock.MagicMock(),
                env="forno",
                datalake_bucket="forno-datalake",
                relative_query_path="gsheets_agents",
                spark_jobs_path="/spark_jobs/base/",
                **kwargs,
            )
        config_service = mock.MagicMock()
        config_service.configs = {}
        group._get_config_service = mock.MagicMock(return_value=config_service)
        return group

    def test_gsheets_clean_sync_omits_empty_metadata_type(self):
        group = self._task_group(job_cluster_engine=mock.MagicMock())
        group._has_any_metadata = mock.MagicMock(return_value=False)
        group._get_metadata_tables = mock.MagicMock(return_value=set())

        group._build_metadata_sync_task(
            source="gsheets",
            sync_mode=group.SINGLE_TABLE,
            layer=LayerEnum.CLEAN.value,
            database_name="gsheets",
            table_name="agents",
        )

        params = group.job_cluster_engine.create_spark_python_task.call_args.kwargs[
            "job_parameters"
        ]
        assert "" not in params
        assert "--metadata-type" not in params
        assert params[-2:] == ["gsheets_agents", "--bypass-propagate"]

    def test_raw_sync_with_metadata_type_uses_flag(self):
        group = self._task_group(job_cluster_engine=mock.MagicMock())

        group._build_metadata_sync_task(
            source="emlio",
            sync_mode=group.SINGLE_TABLE,
            layer=LayerEnum.RAW.value,
            database_name="emlio",
            table_name="emlio_logs",
            metadata_file_type=MetadataTypeEnum.TAGS.value,
        )

        params = group.job_cluster_engine.create_spark_python_task.call_args.kwargs[
            "job_parameters"
        ]
        metadata_type_index = params.index("--metadata-type")
        assert params[metadata_type_index + 1] == MetadataTypeEnum.TAGS.value
        assert params[metadata_type_index + 2] == "gsheets_agents"
