import logging
import json
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import (
    QUERIES_DATALAKE_PATH,
    DatalakeMetastoreService,
)

from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.pipeline.full_table_loader_pipeline import (
    FullTableLoaderPipeline,
)

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
    parser.add_argument("spark_params", type=str, help="parameters to pass to spark")
    parser.add_argument(
        "additional_query_template_params",
        type=str,
        help="additional query parameters not including date params",
    )

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    layer = args.layer
    database_base_name = args.database_base_name
    relative_query_path = args.relative_query_path
    table_name = args.table_name
    execution_date = args.execution_date
    target_database_base_name = args.target_database_base_name
    partitions = json.loads(args.partitions.replace("'", '"'))
    query_template_params = json.loads(
        args.additional_query_template_params.replace("'", '"')
    )
    spark_params = json.loads(args.spark_params)

    logger.info(
        f"m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, layer={layer}, "
        + f"database_base_name={database_base_name}, relative_query_path={relative_query_path}, "
        + f"table_name={table_name},  msg=Job execution started"
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

    query = FileService.get_query_from_file_name(
        f"{QUERIES_DATALAKE_PATH}{relative_query_path}/{layer}/{table_name}.sql"
    )

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
        spark_params=spark_params,
    )
    table_loader_pipeline.run()
