from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseSubDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum


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
                    "python_file": f"{self.spark_job_path}/load_table_to_dw_staging_schema.py",
                    "parameters": [
                        self.env,
                        self.dw_bucket,
                        self.dw_schema,
                        self.relative_query_path,
                        table_name,
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

        duplicity_test = QuintoAndarDatabricksSubmitRunOperator(
            dag=sub_dag,
            task_id=f"test-{slugged_table_name}-duplicity",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_job_path}/duplicity_test.py",
                    "parameters": [self.dw_schema, table_name],
                }
            },
        )

        if test_ods_migration:
            test_entity_ods_migration = QuintoAndarDatabricksSubmitRunOperator(
                dag=sub_dag,
                task_id=f"test-{self.dw_schema}-{slugged_table_name}-ods-migration",
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_job_path}/test_ods_migration.py",
                        "parameters": [
                            self.env,
                            table_name,
                            Variable.get("ODS_MIGRATION_TESTS_THRESHOLD"),
                            "{{ ds }}",
                        ],
                    }
                },
            )
            load_table_to_dw_staging_schema >> test_entity_ods_migration

        load_table_to_dw_staging_schema.set_downstream([duplicity_test, emptiness_test])

        return sub_dag
