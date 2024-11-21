import logging
import json
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService, MetricMetastoreMapping
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.pipeline.full_table_loader_pipeline import FullTableLoaderPipeline


JOB_NAME = "load_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket", type=str, help="datalake bucket")
    parser.add_argument("layer", type=str, help="clean/enrich values to save data to")
    parser.add_argument(
        "database_base_name",
        type=str,
        help="base name for database, e.g. 'source' for raw/clean layer and 'source' and/or 'context' for enrich layer",
    )
    parser.add_argument("target_database_base_name")
    parser.add_argument(
        "relative_query_path",
        type=str,
        help="relative query path for sql file to create table",
    )
    parser.add_argument("table_name", type=str, help="table name that will be created")
    parser.add_argument("partitions")
    parser.add_argument("execution_date")
    parser.add_argument(
        "spark_session_configs",
        type=str,
        help="custom config parameters to be set in spark session",
    )
    parser.add_argument(
        "additional_query_template_params",
        type=str,
        help="additional query parameters not including date params",
    )
    parser.add_argument(
        "schema",
        type=lambda arg: None if not arg else arg,
        help="table schema used in the query path",
    )
    parser.add_argument(
        "tree_path",
        type=lambda arg: None if not arg else arg,
        help="path to reach the query place",
    )
    parser.add_argument(
        "-tp",
        "--table-privileges",
        type=lambda arg: None if not arg else arg,
        help="json string mapping each principal to a list of permissions for the table",
        required=False,
        default=None,
    )

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    layer = args.layer
    database_base_name = args.database_base_name
    relative_query_path = args.relative_query_path
    schema = args.schema
    tree_path = args.tree_path
    table_name = args.table_name
    execution_date = args.execution_date
    target_database_base_name = args.target_database_base_name
    partitions = json.loads(args.partitions.replace("'", '"'))
    query_template_params = json.loads(
        args.additional_query_template_params.replace("'", '"')
    )
    spark_session_configs = json.loads(args.spark_session_configs)
    if args.table_privileges is not None:
        table_privileges_dict = json.loads(args.table_privileges)
    else:
        table_privileges_dict = None

    logger.info(
        f"m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, layer={layer}, "
        + f"database_base_name={database_base_name}, relative_query_path={relative_query_path}, "
        + f"table_name={table_name}, schema={schema}, tree_path={tree_path}, msg=Job execution started"
    )

    dt_datetime = datetime.strptime(execution_date, "%Y-%m-%d")
    dt_dict = dict(
        [
            ("year", dt_datetime.year),
            ("month", dt_datetime.month),
            ("day", dt_datetime.day),
        ]
    )
    query_template_params.update(dt_dict)

    if layer == LayerEnum.METRIC.value:
        metric_ms_mapping = MetricMetastoreMapping(
            bucket=datalake_bucket, source=database_base_name
        )
        database_name, database_location = metric_ms_mapping.get_metric_info()

        metric_ms_mapping = MetricMetastoreMapping(
            bucket=datalake_bucket, source=target_database_base_name
        )
        target_database_name, target_database_location = (
            metric_ms_mapping.get_metric_info()
        )

    else:
        (
            database_name,
            database_location,
            athena_database_name,
        ) = DatalakeMetastoreService.get_layer_info(
            env, database_base_name, datalake_bucket, layer
        )

        (
            target_database_name,
            target_database_location,
            target_athena_database_name,
        ) = DatalakeMetastoreService.get_layer_info(
            env, target_database_base_name, datalake_bucket, layer
        )

    intermediate_path = schema if schema else tree_path

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=relative_query_path,
        layer=layer,
        intermediate_path=intermediate_path,
        table_name=table_name,
    )

    if table_privileges_dict is not None:
        table_privileges = TablePrivileges.from_input_dict(
            table_privileges_dict, f"{database_name}.{table_name}"
        )
    else:
        table_privileges = TablePrivileges.from_environment_default(f"{database_name}.{table_name}")


    table_loader_pipeline = FullTableLoaderPipeline(
        database_name=database_name,
        table_name=table_name,
        database_location=database_location,
        layer=layer,
        query=query,
        partitions=partitions,
        query_template_params=query_template_params,
        target_database_name=target_database_name,
        target_database_location=target_database_location,
        spark_session_configs=spark_session_configs,
        table_privileges=table_privileges,
    )
    table_loader_pipeline.run()
