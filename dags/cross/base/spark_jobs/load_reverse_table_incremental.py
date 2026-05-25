import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db.reverse_metastore_mapping import ReverseMetastoreMapping
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.pipeline.incremental_table_loader_pipeline import (
    IncrementalTableLoaderPipeline,
)

JOB_NAME = "load_reverse_table"

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

    logger.info(
        f"m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, layer={layer}, "
        + f"database_base_name={database_base_name}, relative_query_path={relative_query_path}, "
        + f"table_name={table_name}, schema={schema}, tree_path={tree_path}, msg=Job execution started"
    )
    if execution_date:
        dt_datetime = datetime.strptime(execution_date, "%Y-%m-%d")
        dt_dict = dict(
            [
                ("year", dt_datetime.year),
                ("month", dt_datetime.month),
                ("day", dt_datetime.day),
            ]
        )
        query_template_params.update(dt_dict)

    database_info = ReverseMetastoreMapping(
        database_base_name, datalake_bucket
    ).get_all_reverse_info()
    database_name = database_info["reverse_schema_name"]
    database_location = database_info["reverse_schema_path"]

    target_database_info = ReverseMetastoreMapping(
        target_database_base_name, datalake_bucket
    ).get_all_reverse_info()
    target_database_name = target_database_info["reverse_schema_name"]
    target_database_location = target_database_info["reverse_schema_path"]

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=relative_query_path, layer=layer, table_name=table_name
    )

    table_loader_pipeline = IncrementalTableLoaderPipeline(
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
    )
    table_loader_pipeline.run()
