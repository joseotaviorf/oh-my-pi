import json
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DWMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.pipeline import IncrementalTableLoaderPipeline

JOB_NAME = "load_incremental_table_to_dw_final_schema"

logger = QuintoAndarLogger(JOB_NAME)


def build_query(query_filters, dw_staging_database_name, table_name):

    where = ""
    if query_filters:
        filters = [f"{key} = {value}" for key, value in query_filters.items()]
        where = "WHERE " + " AND ".join(filters)

    query = f"SELECT * FROM {dw_staging_database_name}.{table_name} {where}"

    return query


if __name__ == "__main__":

    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("dw_bucket")
    parser.add_argument("dw_schema")
    parser.add_argument("table_name")
    parser.add_argument("partitions")
    parser.add_argument("execution_date")
    parser.add_argument("query_filters")

    args = parser.parse_args()

    env = args.env
    dw_bucket = args.dw_bucket
    dw_schema = args.dw_schema
    table_name = args.table_name
    partitions = json.loads(args.partitions.replace("'", '"'))
    query_filters = json.loads(args.query_filters)
    execution_date = args.execution_date

    logger.info(
        f"m={__name__}, env={env}, dw_bucket={dw_bucket}, dw_schema={dw_schema}, "
        f"table_name={table_name}, execution_date={execution_date}, msg=Job execution started"
    )

    dw_db_name, dw_db_location = DWMetastoreService.get_layer_info(
        env=env, schema=dw_schema, bucket=dw_bucket, layer=LayerEnum.DW.value
    )

    dw_staging_db_name, _ = DWMetastoreService.get_layer_info(
        env=env, schema=dw_schema, bucket=dw_bucket, layer=LayerEnum.DW_STAGING.value
    )

    dt_datetime = datetime.strptime(execution_date, "%Y-%m-%d")
    query_template_params = {
        "year": dt_datetime.year,
        "month": dt_datetime.month,
        "day": dt_datetime.day,
    }

    query = build_query(query_filters, dw_staging_db_name, table_name)

    table_loader_pipeline = IncrementalTableLoaderPipeline(
        database_name=dw_db_name,
        table_name=table_name,
        database_location=dw_db_location,
        layer=LayerEnum.DW.value,
        query=query,
        partitions=partitions,
        query_template_params=query_template_params,
    )
    table_loader_pipeline.run()
