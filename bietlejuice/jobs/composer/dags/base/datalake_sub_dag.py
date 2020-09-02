from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseSubDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum


class DatalakeSubDAG(BaseSubDAG):
    """
    Responsible for creating a subdag to load a table to metastore (Spark and Athena)
    """

    def __init__(
        self,
        dag_id,
        start_date,
        env,
        datalake_bucket,
        database_base_name,
        layer,
        relative_query_path,
        spark_job_paths,
        athena_query_result_location,
        schedule_interval=None,
        target_database_base_name=None,
        spark_params={},
    ):
        """
        :param dag_id: main dag id to attach subdag to
        :param start_date: start date
        :param env: forno or prod environments
        :param layer: LayerEnum.ENRICH or LayerEnum.CLEAN values
        :param datalake_bucket: datalake bucket in S3
        :param database_base_name: database base name for the source table database
        :param relative_query_path: relative query path from default queries path containing sql file for the table
        to be created
        :param spark_job_paths: paths for spark jobs used in subdag tasks
        :param athena_query_result_location: athena query results location
        :param schedule_interval: schedule interval
        :param target_database_base_name database base name for the target table database
        """
        self.dag_id = dag_id
        self.start_date = start_date
        self.env = env
        self.datalake_bucket = datalake_bucket
        self.database_base_name = database_base_name
        self.relative_query_path = relative_query_path
        self.spark_job_paths = spark_job_paths
        self.athena_query_result_location = athena_query_result_location
        self.schedule_interval = schedule_interval
        self.target_database_base_name = (
            target_database_base_name
            if target_database_base_name
            else database_base_name
        )
        self.spark_params = spark_params

        if layer not in [LayerEnum.CLEAN, LayerEnum.ENRICH]:
            raise ValueError(f"m=__init__, layer={layer}, msg=The layer is invalid.")

        self.layer = layer

    def build_subdag(
        self,
        sub_dag_name,
        table_name,
        slugged_table_name,
        test_ods_migration=False,
        partitions=None,
        is_incremental=False,
        extra_query_template_params=None,
    ):
        """
        Create a subdag containing 2 tasks:
        1. load table to metastore database using a sql query
        2. create a external table in Athena using metastore created before
        :param sub_dag_name: subdag name
        :param table_name: table name to be created
        :param slugged_table_name: slugged table name for subdag
        :param test_ods_migration: just to be compatible with the base class
        :param partitions: list of columns to partition table
        :param is_incremental: if this table uses incremental load type
        :return: the subdag created
        """

        partitions = partitions or []
        extra_query_template_params = extra_query_template_params or {}

        sub_dag = BaseSubDAG(
            sub_dag_name=sub_dag_name,
            dag_name=self.dag_id,
            schedule_interval=self.schedule_interval,
            start_date=self.start_date,
            layer=self.layer,
        )._build_local_dag()

        load_table = QuintoAndarDatabricksSubmitRunOperator(
            task_id=f"load-{self.layer.value}-{slugged_table_name}",
            dag=sub_dag,
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_job_paths}/load_table.py",
                    "parameters": [
                        self.env,
                        self.datalake_bucket,
                        self.layer.value,
                        self.database_base_name,
                        self.target_database_base_name,
                        self.relative_query_path,
                        table_name,
                        str(partitions),
                        "{{ ds }}",
                        is_incremental,
                        str(self.spark_params),
                        str(extra_query_template_params),
                    ],
                }
            },
        )

        create_external_table = QuintoAndarDatabricksSubmitRunOperator(
            dag=sub_dag,
            task_id=f"create-{self.layer.value}-{slugged_table_name}-external-table",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_job_paths}/create_external_table.py",
                    "parameters": [
                        self.env,
                        self.datalake_bucket,
                        self.athena_query_result_location,
                        self.layer.value,
                        self.target_database_base_name,
                        table_name,
                        str(partitions),
                        is_incremental,
                    ],
                }
            },
        )

        load_table >> create_external_table

        return sub_dag
