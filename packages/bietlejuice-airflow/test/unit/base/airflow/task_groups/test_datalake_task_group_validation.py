from unittest import mock

from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestDatalakeTaskGroupValidation:
    def _task_group(self, is_validation: bool) -> DatalakeTaskGroup:
        with mock.patch(
            "bietlejuice.base.airflow.task_groups.datalake_task_group.ConfigurationService"
        ) as mock_config_svc:
            mock_config_svc.return_value.get_config.return_value = "mock_bucket"
            return DatalakeTaskGroup(
                dag=mock.MagicMock(),
                env="prod",
                datalake_bucket="prod-datalake",
                relative_query_path="enrich_foo",
                spark_jobs_path="/spark_jobs",
                is_validation=is_validation,
            )

    def test_validation_appends_target_spark_args(self):
        group = self._task_group(is_validation=True)
        with (
            mock.patch(
                "bietlejuice.base.airflow.task_groups.datalake_task_group.chain"
            ),
            mock.patch.object(
                group, "_build_load_task", return_value=mock.MagicMock()
            ) as build_load_task,
            mock.patch.object(
                group, "_build_metadata_sync_task", return_value=mock.MagicMock()
            ),
            mock.patch.object(group, "_get_data_quality_tables", return_value=set()),
        ):
            group._build_task_group(
                layer=LayerEnum.ENRICH,
                source_database_base_name="enrich",
                target_database_base_name="enrich",
                table_name="my_table",
                partitions=["year"],
            )

        spark_job_extra_args = build_load_task.call_args.kwargs["spark_job_extra_args"]
        assert "--target-database-name" in spark_job_extra_args
        assert "cluster_validation" in spark_job_extra_args
        assert "--target-table-name" in spark_job_extra_args

    def test_validation_uses_target_schema_for_write_path(self):
        group = self._task_group(is_validation=True)
        with (
            mock.patch(
                "bietlejuice.base.airflow.task_groups.datalake_task_group.chain"
            ),
            mock.patch.object(
                group, "_build_load_task", return_value=mock.MagicMock()
            ) as build_load_task,
            mock.patch.object(
                group, "_build_metadata_sync_task", return_value=mock.MagicMock()
            ),
            mock.patch.object(group, "_get_data_quality_tables", return_value=set()),
        ):
            group._build_task_group(
                layer=LayerEnum.ENRICH,
                source_database_base_name="source_schema",
                target_database_base_name="target_schema",
                table_name="my_table",
                partitions=["year"],
            )

        spark_job_extra_args = build_load_task.call_args.kwargs["spark_job_extra_args"]
        target_table_idx = spark_job_extra_args.index("--target-table-name") + 1
        assert (
            spark_job_extra_args[target_table_idx]
            == "datalake_target_schema___my_table"
        )

    def test_prod_does_not_append_target_spark_args(self):
        group = self._task_group(is_validation=False)
        with (
            mock.patch(
                "bietlejuice.base.airflow.task_groups.datalake_task_group.chain"
            ),
            mock.patch.object(
                group, "_build_load_task", return_value=mock.MagicMock()
            ) as build_load_task,
            mock.patch.object(
                group, "_build_metadata_sync_task", return_value=mock.MagicMock()
            ),
            mock.patch.object(group, "_get_data_quality_tables", return_value=set()),
        ):
            group._build_task_group(
                layer=LayerEnum.ENRICH,
                source_database_base_name="enrich",
                target_database_base_name="enrich",
                table_name="my_table",
                partitions=["year"],
            )

        spark_job_extra_args = build_load_task.call_args.kwargs["spark_job_extra_args"]
        assert "--target-database-name" not in spark_job_extra_args

    def test_validation_skips_dataset_attachment(self):
        group = self._task_group(is_validation=True)
        with (
            mock.patch(
                "bietlejuice.base.airflow.task_groups.datalake_task_group.QuintoAndarDatabricksSubmitRunOperator",
                return_value=mock.MagicMock(),
            ),
            mock.patch(
                "bietlejuice.base.airflow.task_groups.datalake_task_group.DatasetAdder.attach_dataset_to_task"
            ) as attach_dataset,
        ):
            group._build_load_task(
                task_id="test_task",
                extraction_spark_job_file="/spark_jobs/load_table_full.py",
                do_output_xcom_push=False,
                spark_job_extra_args=[],
            )

        attach_dataset.assert_not_called()

    def test_prod_attaches_dataset(self):
        group = self._task_group(is_validation=False)
        with (
            mock.patch(
                "bietlejuice.base.airflow.task_groups.datalake_task_group.QuintoAndarDatabricksSubmitRunOperator",
                return_value=mock.MagicMock(),
            ),
            mock.patch(
                "bietlejuice.base.airflow.task_groups.datalake_task_group.DatasetAdder.attach_dataset_to_task"
            ) as attach_dataset,
        ):
            group._build_load_task(
                task_id="test_task",
                extraction_spark_job_file="/spark_jobs/load_table_full.py",
                do_output_xcom_push=False,
                spark_job_extra_args=[],
            )

        attach_dataset.assert_called_once()
