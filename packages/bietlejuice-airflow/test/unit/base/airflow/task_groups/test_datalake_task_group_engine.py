from unittest import mock

from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup


class TestDatalakeTaskGroupJobClusterEngine:
    def test_build_load_task_uses_engine_when_provided(self):
        engine = mock.MagicMock()
        engine.create_spark_python_task.return_value = mock.MagicMock()
        with mock.patch(
            "bietlejuice.base.airflow.task_groups.datalake_task_group.ConfigurationService"
        ) as mock_config_svc:
            mock_config_svc.return_value.get_config.return_value = "mock_bucket"
            group = DatalakeTaskGroup(
                dag=mock.MagicMock(),
                env="prod",
                datalake_bucket="prod-datalake",
                relative_query_path="gsheets_agents",
                spark_jobs_path="/spark_jobs/base/",
                job_cluster_engine=engine,
            )

        group._build_load_task(
            task_id="load-raw-gsheets-t",
            extraction_spark_job_file="/spark_jobs/base/load_gsheets_into_datalake.py",
            do_output_xcom_push=False,
            pool="gsheets_pool",
            spark_job_extra_args=["extra"],
        )

        engine.create_spark_python_task.assert_called_once()

    def test_build_load_task_falls_back_to_submit_run_without_engine(self):
        with (
            mock.patch(
                "bietlejuice.base.airflow.task_groups.datalake_task_group.ConfigurationService"
            ) as mock_config_svc,
            mock.patch(
                "bietlejuice.base.airflow.task_groups.datalake_task_group.QuintoAndarDatabricksSubmitRunOperator",
                return_value=mock.MagicMock(),
            ) as submit_run,
            mock.patch(
                "bietlejuice.base.airflow.task_groups.datalake_task_group.DatasetAdder.attach_dataset_to_task"
            ),
        ):
            mock_config_svc.return_value.get_config.return_value = "mock_bucket"
            group = DatalakeTaskGroup(
                dag=mock.MagicMock(),
                env="prod",
                datalake_bucket="prod-datalake",
                relative_query_path="metric_foo",
                spark_jobs_path="/spark_jobs/base/",
            )
            group._build_load_task(
                task_id="load-metric-t",
                extraction_spark_job_file="/spark_jobs/base/load_table_full.py",
                do_output_xcom_push=False,
                spark_job_extra_args=[],
            )

        submit_run.assert_called_once()
