import logging
import json
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DWMetastoreService
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.pipeline import IncrementalTableLoaderPipeline

JOB_NAME = "load_table_to_dw_final_schema"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def build_query(query_filters, database_name_staging, table_name):

    filters = ""
    if query_filters:
        filters = "\nWHERE 1=1"
        for key, value in query_filters.items():
            filters += f"\n and {key} = {value}"

    query = f"SELECT * FROM {database_name_staging}.{table_name}{filters}"

    return query


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("dw_bucket", type=str, help="dw bucket")
    parser.add_argument("dw_schema", type=str, help="dw schema")
    parser.add_argument("table_name", type=str, help="table name that will be created")
    parser.add_argument("partitions")
    parser.add_argument("execution_date")
    parser.add_argument("is_incremental")
    parser.add_argument("query_filters")

    args = parser.parse_args()

    env = args.env
    dw_bucket = args.dw_bucket
    dw_schema = args.dw_schema
    table_name = args.table_name
    partitions = json.loads(args.partitions.replace("'", '"'))
    query_filters = json.loads(args.query_filters)
    execution_date = args.execution_date
    is_incremental = args.is_incremental == "True"

    logger.info(
        f"m={JOB_NAME}, env={env}, dw_bucket={dw_bucket}, dw_schema={dw_schema}, table_name={table_name}, "
        + "msg=Job execution started"
    )

    schema_database_name, schema_database_location = DWMetastoreService.get_layer_info(
        env, dw_schema, dw_bucket, "schema"
    )

    database_name_staging, database_location_staging = DWMetastoreService.get_layer_info(
        env, dw_schema, dw_bucket, "staging"
    )

    dt_datetime = datetime.strptime(execution_date, "%Y-%m-%d")
    query_template_params = {
        "year": dt_datetime.year,
        "month": dt_datetime.month,
        "day": dt_datetime.day,
    }

    query = build_query(query_filters, database_name_staging, table_name)

    table_loader_pipeline = IncrementalTableLoaderPipeline(
        database_name=schema_database_name,
        table_name=table_name,
        database_location=schema_database_location,
        layer=LayerEnum.DW.value,
        query=query,
        partitions=partitions,
        query_template_params=query_template_params,
    )
    table_loader_pipeline.run()
