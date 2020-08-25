import logging
from argparse import ArgumentParser
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.pipeline.create_external_table_pipeline import (
    CreateExternalTablePipeline,
)


JOB_NAME = "create_external_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket", type=str, help="datalake bucket")
    parser.add_argument(
        "athena_query_result_location", type=str, help="athena query results location"
    )
    parser.add_argument("layer", type=str, help="raw/clean/enrich values")
    parser.add_argument(
        "database_base_name",
        type=str,
        help="base name for database, e.g. 'source' for raw/clean layer and 'source' and/or 'context' for enrich layer",
    )
    parser.add_argument("table_name", type=str, help="table name")

    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location
    layer = args.layer
    database_base_name = args.database_base_name
    table_name = args.table_name

    logger.info(
        f"m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, "
        + f"athena_query_result_location={athena_query_result_location}, layer={layer}, "
        + f"database_base_name={database_base_name}, table_name={table_name}, msg=Job execution started"
    )
    spark_database_name, database_location, athena_database_name = DatalakeMetastoreService.get_layer_info(
        env, database_base_name, datalake_bucket, layer
    )
    format_options = TableStorageFormat.get_storage(layer)

    create_external_table_pipeline = CreateExternalTablePipeline(
        athena_query_result_location,
        athena_database_name,
        table_name,
        database_location,
        format_options,
        spark_database_name,
    )
    create_external_table_pipeline.run()
