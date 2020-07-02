from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseSubDAG


class DWSubDAG(BaseSubDAG):
    """
    Responsible for creating a subdag to load a table in DW layer (metastore and Redshift)
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
        spectrum_iam_role,
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
        :param spectrum_iam_role: spectrum iam role to copy table files to Redshift
        :param schedule_interval: schedule interval
        """
        self.dag_id = dag_id
        self.start_date = start_date
        self.env = env
        self.dw_bucket = dw_bucket
        self.dw_schema = dw_schema
        self.relative_query_path = relative_query_path
        self.spark_job_path = spark_job_path
        self.spectrum_iam_role = spectrum_iam_role
        self.schedule_interval = schedule_interval

    def build_subdag(
        self, sub_dag_name, table_name, slugged_table_name, test_ods_migration
    ):
        sub_dag = BaseSubDAG(
            sub_dag_name=sub_dag_name,
            dag_name=self.dag_id,
            schedule_interval=self.schedule_interval,
            start_date=self.start_date,
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

        load_table_to_dw_final_schema = QuintoAndarDatabricksSubmitRunOperator(
            dag=sub_dag,
            task_id=f"load-{slugged_table_name}-into-dw-{self.dw_schema}",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_job_path}/load_table_to_dw_final_schema.py",
                    "parameters": [
                        self.env,
                        self.dw_bucket,
                        self.dw_schema,
                        table_name,
                    ],
                }
            },
        )

        load_table_to_redshift = QuintoAndarDatabricksSubmitRunOperator(
            dag=sub_dag,
            task_id=f"load-{slugged_table_name}-into-redshift",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_job_path}/load_table_to_redshift.py",
                    "parameters": [
                        self.env,
                        self.spectrum_iam_role,
                        self.dw_bucket,
                        self.dw_schema,
                        table_name,
                    ],
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
                        "parameters": [self.env, table_name, "{{ ds }}"],
                    }
                },
            )
            load_table_to_dw_staging_schema >> test_entity_ods_migration >> load_table_to_dw_final_schema
        else:
            load_table_to_dw_staging_schema >> load_table_to_dw_final_schema

        load_table_to_dw_final_schema >> load_table_to_redshift

        return sub_dag
