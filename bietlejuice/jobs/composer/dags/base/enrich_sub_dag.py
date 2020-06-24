from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseSubDAG


class EnrichSubDAG(BaseSubDAG):
    """
    Responsible for creating a subdag to load a enriched table to metastore (Spark and Athena)
    """

    def __init__(
        self,
        dag_id,
        start_date,
        env,
        datalake_bucket,
        database_base_name,
        relative_query_path,
        spark_job_paths,
        athena_query_result_location,
        schedule_interval=None,
    ):
        """
        :param dag_id: main dag id to attach subdag to
        :param start_date: start date
        :param env: forno or prod environments
        :param datalake_bucket: datalake bucket in S3
        :param database_base_name: database base name for the table database
        :param relative_query_path: relative query path from default queries path containing sql file for the table
        to be created
        :param spark_job_paths: paths for spark jobs used in subdag tasks
        :param athena_query_result_location: athena query results location
        :param schedule_interval: schedule interval
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

    def build_subdag(self, sub_dag_name, table_name, slugged_table_name):
        """
        Create a subdag containing 2 tasks:
        1. load table to enriched metastore database using a sql query
        2. create a external table in Athena using metastore created before
        :param sub_dag_name: subdag name
        :param table_name: table name to be created
        :param slugged_table_name: slugged table name for subdag
        :return: the subdag created
        """
        sub_dag = BaseSubDAG(
            sub_dag_name=sub_dag_name,
            dag_name=self.dag_id,
            schedule_interval=self.schedule_interval,
            start_date=self.start_date,
        )._build_local_dag()

        enrich_table = QuintoAndarDatabricksSubmitRunOperator(
            task_id=f"enrich-{slugged_table_name}",
            dag=sub_dag,
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_job_paths}/enrich_table.py",
                    "parameters": [
                        self.env,
                        self.datalake_bucket,
                        "enrich",
                        self.database_base_name,
                        self.relative_query_path,
                        table_name,
                    ],
                }
            },
        )

        create_external_table = QuintoAndarDatabricksSubmitRunOperator(
            dag=sub_dag,
            task_id=f"create-enrich-{slugged_table_name}-external-table",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_job_paths}/create_external_table.py",
                    "parameters": [
                        self.env,
                        self.datalake_bucket,
                        self.athena_query_result_location,
                        "enrich",
                        self.database_base_name,
                        table_name,
                    ],
                }
            },
        )

        enrich_table >> create_external_table

        return sub_dag
