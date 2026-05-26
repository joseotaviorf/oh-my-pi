import json
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db.dw_metastore_service import DWMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.pipeline.incremental_table_loader_pipeline import (
    IncrementalTableLoaderPipeline,
)

JOB_NAME = "load_incremental_dw"

logger = QuintoAndarLogger(JOB_NAME)


def build_query(extra_query_template_params, dw_staging_database_name, table_name):

    where = ""
    if extra_query_template_params:
        filters = [
            f"{key} = {value}" for key, value in extra_query_template_params.items()
        ]
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
    parser.add_argument("extra_query_template_params")
    parser.add_argument(
        "-tdn",
        "--target-database-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
    )
    parser.add_argument(
        "-ttn",
        "--target-table-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
    )

    args = parser.parse_args()

    env = args.env
    dw_bucket = args.dw_bucket
    dw_schema = args.dw_schema
    table_name = args.table_name
    partitions = json.loads(args.partitions.replace("'", '"'))
    extra_query_template_params = json.loads(args.extra_query_template_params)
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

    source_table_name = table_name
    write_table_name = table_name
    target_database_name = dw_db_name
    target_database_location = dw_db_location
    read_database_name = dw_staging_db_name
    read_table_name = source_table_name
    if args.target_database_name and args.target_table_name:
        from bietlejuice.base.validation.target_resolver import (
            resolve_validation_target,
            validation_dw_database_location,
        )

        read_database_name, read_table_name = resolve_validation_target(
            dw_staging_db_name, source_table_name
        )
        target_database_name = args.target_database_name
        write_table_name = args.target_table_name
        target_database_location = validation_dw_database_location(
            dw_bucket, dw_db_name
        )

    query = build_query(
        extra_query_template_params, read_database_name, read_table_name
    )

    table_loader_pipeline = IncrementalTableLoaderPipeline(
        database_name=dw_db_name,
        table_name=write_table_name,
        database_location=dw_db_location,
        layer=LayerEnum.DW.value,
        query=query,
        partitions=partitions,
        query_template_params=query_template_params,
        target_database_name=target_database_name,
        target_database_location=target_database_location,
    )
    table_loader_pipeline.run()
