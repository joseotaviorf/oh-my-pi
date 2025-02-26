from bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher import (
    FactoryDispatcher,
)
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.formatters import StringFormatter
from bietlejuice_plugin.transfer_data_plugin import QuintoAndarPostgresToS3Operator

SOURCE = "astro"
QUERY_PATH = DAGPackagesPathService.get_dag_path(SOURCE) + "/queries/raw/"

dag_declaration = {
    "dag": {
        "name": SOURCE,
        "owner": "Data Ingestion",
        "schedule_interval": "0 5-18/1 * * *",
        "documentation": {
            "dag_purpose": "Dumps the Airflow database into S3. To know more about airflow's tables"
            "take a look [here](https://www.astronomer.io/guides/airflow-database)."
        },
    },
    "workflow": {
        "layer": "raw",
        "type": "custom_ingestion",
        "load_spark_job": "update_metastore",
        "spark_job_arguments": [
            "{environment}",
            "{bucket}",
            "{dag_name}",
            "{table_name}",
        ],
        "default_extraction_type": "incremental",
        "default_partitions": ["year", "month", "day"],
        "tables_customization": {
            "dag": {"has_query": False},
            "dag_run": {"has_query": True},
            "log": {"has_query": True},
            "task_fail": {"has_query": False},
            "task_instance": {"has_query": True},
            "task_instance_history": {"has_query": True},
            "serialized_dag": {"has_query": True},
        },
    },
    "cluster": {"type": "databricks_13_3_min_io-memory_cluster"},
}
factory = FactoryDispatcher(layer=LayerEnum.RAW).get_factory(
    dag_args=dag_declaration["dag"],
    workflow_args=dag_declaration["workflow"],
    cluster_args=dag_declaration["cluster"],
)
dag_workflow = factory.get_workflow()
dag = dag_workflow.build_dag()


def get_sql_from_table_name(table_name: str) -> str:
    """
    Search and get a sql given a table_name

    :param table_name: table name
    :type table_name: str
    :return: the query to built the given table.
    :rtype: str
    """
    sql = DAGPackagesPathService._read_file_content_from_filesystem(
        QUERY_PATH + f"{table_name}.sql"
    )

    return sql


def create_extraction_task(
    table_name: str, has_query: bool = False
) -> QuintoAndarPostgresToS3Operator:
    """
    Create a task to load table from Airflow database to S3.
    In this way, the first step of raw creation is executed
    outside a spark job. When incremental is used, this functions
    breaks the load in two to keep a d-1 ingestion, but to add
    a fraction of today data (This happens to keep data fresh for
    some pulses).

    :param table_name: table name
    :type table_name: str
    :param has_query: if a query will be used or the table will be consumed asis
    :type has_query: bool
    :return: An airflow task
    :rtype: QuintoAndarPostgresToS3Operator
    """
    slugged_table_name = StringFormatter.slugify(table_name)
    s3_suffix = "/year={{ execution_date.year }}/month={{ execution_date.month }}/day={{ execution_date.day }}"

    sql = get_sql_from_table_name(table_name) if has_query else None

    if sql:
        sql = sql.format(
            load_start_date=dag_workflow.dag_execution_context.load_start_date,
            load_end_date=dag_workflow.dag_execution_context.load_end_date
        )

    raw_task = QuintoAndarPostgresToS3Operator(
        dag=dag,
        table=table_name,
        sql=sql,
        task_id=f"load-raw-to-s3-{slugged_table_name}",
        bucket=dag_workflow.dag_execution_context.bucket,
        filename="data.json",
        s3_file_path="raw/astro/{table_name}{s3_suffix}".format(
            table_name=table_name, s3_suffix=s3_suffix
        ),
        database_conn_id="airflow_db",
    )

    return raw_task


execute_job_cluster_task = dag.get_task("execute-job-cluster")

for table_name, table_customization in dag_declaration["workflow"][
    "tables_customization"
].items():
    has_query = table_customization.get("has_query", False)
    task = create_extraction_task(table_name, has_query)
    task >> execute_job_cluster_task
