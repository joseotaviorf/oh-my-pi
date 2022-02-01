import json

from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseSubDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import ConfigurationService


class DWStagingSubDAG(BaseSubDAG):
    """
    Responsible for creating a subdag to load a table in DW staging layer and apply quality and integrity tests to it
    """

    def __init__(
        self,
        dag_id,
        start_date,
        env,
        dw_bucket,
        dw_schema,
        relative_query_path,
        spark_job_path,
        schedule_interval=None,
        cluster_config_params={},
    ):
        """
        :param dag_id: main dag id to attach subdag to
        :param start_date: start date
        :param env: forno or prod environments
        :param dw_bucket: dw bucket in S3
        :param dw_schema: dw schema name
        :param relative_query_path: relative query path from default queries path containing sql file for the table
        to be created
        :param spark_job_path: paths for spark jobs used in subdag tasks
        :param schedule_interval: schedule interval
        :param cluster_config_params: custom config parameters to be set in spark cluster
        """
        self.dag_id = dag_id
        self.start_date = start_date
        self.env = env
        self.dw_bucket = dw_bucket
        self.dw_schema = dw_schema
        self.relative_query_path = relative_query_path
        self.spark_job_path = spark_job_path
        self.schedule_interval = schedule_interval
        self.layer = LayerEnum.DW_STAGING
        self.cluster_config_params = cluster_config_params

    def build_subdag(
        self, sub_dag_name, table_name, slugged_table_name, test_ods_migration
    ):
        sub_dag = BaseSubDAG(
            sub_dag_name=sub_dag_name,
            dag_name=self.dag_id,
            schedule_interval=self.schedule_interval,
            start_date=self.start_date,
            layer=self.layer,
        )._build_local_dag()

        load_table_to_dw_staging_schema = QuintoAndarDatabricksSubmitRunOperator(
            dag=sub_dag,
            task_id=f"load-{slugged_table_name}-into-dw-{self.dw_schema}-staging",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_job_path}/load_full_table_to_dw_staging_schema.py",
                    "parameters": [
                        self.env,
                        self.dw_bucket,
                        self.dw_schema,
                        self.relative_query_path,
                        table_name,
                        str(self.cluster_config_params),
                    ],
                }
            },
        )

        emptiness_test = QuintoAndarDatabricksSubmitRunOperator(
            dag=sub_dag,
            task_id=f"test-{slugged_table_name}-emptiness",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_job_path}/emptiness_test.py",
                    "parameters": [self.dw_schema, table_name],
                }
            },
        )

        test_tasks = [emptiness_test]
        if test_ods_migration:
            config_service = ConfigurationService()
            ods_migration_tests_threshold = config_service.get_config(
                "ods_migration_tests_threshold"
            )
            test_entity_ods_migration = QuintoAndarDatabricksSubmitRunOperator(
                dag=sub_dag,
                task_id=f"test-{self.dw_schema}-{slugged_table_name}-ods-migration",
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_job_path}/test_ods_migration.py",
                        "parameters": [
                            self.env,
                            table_name,
                            json.dumps(
                                ods_migration_tests_threshold
                            ),  # TODO [ODS] Remove this task
                            "{{ ds }}",
                        ],
                    }
                },
            )
            test_tasks.append(test_entity_ods_migration)

        if self.is_dim(table_name):
            add_default_row_to_dim = QuintoAndarDatabricksSubmitRunOperator(
                dag=sub_dag,
                task_id=f"add-default-row-to-{slugged_table_name}",
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_job_path}/add_default_row_to_dim.py",
                        "parameters": [
                            self.env,
                            self.dw_bucket,
                            self.dw_schema,
                            self.layer.value,
                            table_name,
                        ],
                    }
                },
            )
            load_table_to_dw_staging_schema.set_downstream(add_default_row_to_dim)
            add_default_row_to_dim.set_downstream(test_tasks)
        else:
            load_table_to_dw_staging_schema.set_downstream(test_tasks)

        return sub_dag

    @staticmethod
    def is_dim(table_name):
        return table_name.startswith("dim_")
