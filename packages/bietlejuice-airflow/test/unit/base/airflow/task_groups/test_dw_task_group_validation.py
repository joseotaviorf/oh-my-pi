import json
from unittest import mock

from bietlejuice.base.airflow.task_groups.dw_task_group import DWTaskGroup
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestDWTaskGroupValidation:
    def _task_group(self, is_validation: bool) -> DWTaskGroup:
        dag = mock.MagicMock()
        return DWTaskGroup(
            dag=dag,
            env="prod",
            dw_bucket="prod-dw",
            dw_schema="foo",
            relative_query_path="dw_foo",
            spark_jobs_path="/spark_jobs",
            is_validation=is_validation,
        )

    def test_validation_appends_target_spark_args_for_staging(self):
        group = self._task_group(is_validation=True)
        with (
            mock.patch("bietlejuice.base.airflow.task_groups.dw_task_group.chain"),
            mock.patch.object(group, "_build_metadata_sync_task", return_value=None),
            mock.patch.object(group, "_set_data_quality_tasks", return_value=[]),
            mock.patch.object(group, "_set_default_dim_row_task", return_value=[]),
            mock.patch.object(
                group, "_set_load_task", return_value=mock.MagicMock()
            ) as load_task,
        ):
            group._build_task_group(
                layer=LayerEnum.DW_STAGING.value,
                table_name="dim_bar",
                is_incremental=False,
                partitions=["year"],
            )

        spark_job_extra_args = load_task.call_args.kwargs["spark_job_extra_args"]
        assert "--target-database-name" in spark_job_extra_args
        assert "cluster_validation" in spark_job_extra_args
        assert "--target-table-name" in spark_job_extra_args
        assert "dw_foo_staging___dim_bar" in spark_job_extra_args

    def test_prod_does_not_append_target_spark_args(self):
        group = self._task_group(is_validation=False)
        with (
            mock.patch("bietlejuice.base.airflow.task_groups.dw_task_group.chain"),
            mock.patch.object(group, "_build_metadata_sync_task", return_value=None),
            mock.patch.object(group, "_set_data_quality_tasks", return_value=[]),
            mock.patch.object(group, "_set_default_dim_row_task", return_value=[]),
            mock.patch.object(
                group, "_set_load_task", return_value=mock.MagicMock()
            ) as load_task,
        ):
            group._build_task_group(
                layer=LayerEnum.DW_STAGING.value,
                table_name="dim_bar",
                is_incremental=False,
                partitions=["year"],
            )

        spark_job_extra_args = load_task.call_args.kwargs["spark_job_extra_args"]
        assert "--target-database-name" not in spark_job_extra_args

    def test_validation_skips_dataset_attachment(self):
        group = self._task_group(is_validation=True)
        with (
            mock.patch(
                "bietlejuice.base.airflow.task_groups.dw_task_group.QuintoAndarDatabricksCheckJobTaskOperator",
                return_value=mock.MagicMock(),
            ),
            mock.patch(
                "bietlejuice.base.airflow.task_groups.dw_task_group.DatasetAdder.attach_dataset_to_task"
            ) as attach_dataset,
        ):
            group._set_load_task(
                layer=LayerEnum.DW.value,
                schema="foo",
                table_name="dim_bar",
                extraction_type="full",
                spark_job_extra_args=[json.dumps([])],
            )

        attach_dataset.assert_not_called()
