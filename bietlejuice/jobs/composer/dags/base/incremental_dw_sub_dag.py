import json

from bietlejuice.jobs.composer.dags.base.dw_staging_sub_dag import DWStagingSubDAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.airflow import BaseSubDAG
from airflow.models import Variable

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"


class IncrementalDWSubDAG(DWStagingSubDAG):
    def build_subdag(
        self,
        sub_dag_name,
        table_name,
        slugged_table_name,
        test_ods_migration,
        spectrum_iam_role,
        partitions=None,
        extra_query_template_params=None,
        dw_query_filters=None,
    ):

        partitions = partitions or []
        extra_query_template_params = extra_query_template_params or {}
        dw_query_filters = dw_query_filters or {}

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
                    "python_file": f"{self.spark_job_path}load_incremental_table_to_dw_staging_schema.py",
                    "parameters": [
                        self.env,
                        self.dw_bucket,
                        self.dw_schema,
                        self.relative_query_path,
                        table_name,
                        str(partitions),
                        "{{ ds }}",
                        json.dumps(extra_query_template_params),
                        str(self.spark_params),
                    ],
                }
            },
        )

        load_table_to_dw_final_schema = QuintoAndarDatabricksSubmitRunOperator(
            dag=sub_dag,
            task_id=f"load-{slugged_table_name}-into-dw-{self.dw_schema}",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_job_path}load_incremental_table_to_dw_final_schema.py",
                    "parameters": [
                        self.env,
                        self.dw_bucket,
                        self.dw_schema,
                        table_name,
                        str(partitions),
                        "{{ ds }}",
                        json.dumps(dw_query_filters),
                    ],
                }
            },
        )

        load_table_to_redshift = QuintoAndarDatabricksSubmitRunOperator(
            dag=sub_dag,
            task_id=f"load-{slugged_table_name}-into-redshift",
            json={
                "spark_python_task": {
                    "python_file": f"{BASE_SPARK_JOBS_PATH}load_table_to_redshift.py",
                    "parameters": [
                        self.env,
                        spectrum_iam_role,
                        self.dw_bucket,
                        self.dw_schema,
                        table_name,
                    ],
                }
            },
        )

        sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=sub_dag,
            task_id="sync-hive-metastore-table",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_job_path}/sync_metastore_tables.py",
                    "parameters": [
                        self.dw_bucket,
                        LayerEnum.DW.value,
                        self.dw_schema,
                        "--table-name",
                        table_name,
                    ],
                }
            },
        )

        validate_sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=sub_dag,
            task_id="validate-sync-hive-metastore-table",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_job_path}/validate_sync_metastore_tables.py",
                    "parameters": [
                        LayerEnum.DW.value,
                        self.dw_schema,
                        "--table-name",
                        table_name,
                    ],
                }
            },
        )

        load_table_to_dw_final_schema >> sync_metastore_table_task >> validate_sync_metastore_table_task
        load_table_to_dw_staging_schema >> load_table_to_dw_final_schema >> load_table_to_redshift

        return sub_dag
