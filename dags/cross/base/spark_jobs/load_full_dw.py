import json
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db.dw_metastore_service import DWMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.pipeline.full_table_loader_pipeline import FullTableLoaderPipeline

JOB_NAME = "load_full_dw"

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("dw_bucket")
    parser.add_argument("dw_schema")
    parser.add_argument("table_name")
    parser.add_argument("partitions")
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

    logger.info(
        f"m={__name__}, env={env}, dw_bucket={dw_bucket}, dw_schema={dw_schema}, "
        f"table_name={table_name}, msg=Job execution started"
    )

    dw_db_name, dw_db_location = DWMetastoreService.get_layer_info(
        env=env, schema=dw_schema, bucket=dw_bucket, layer=LayerEnum.DW.value
    )

    dw_staging_db_name, _ = DWMetastoreService.get_layer_info(
        env=env, schema=dw_schema, bucket=dw_bucket, layer=LayerEnum.DW_STAGING.value
    )

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

    query = f"SELECT * FROM {read_database_name}.{read_table_name}"

    table_loader_pipeline = FullTableLoaderPipeline(
        database_name=dw_db_name,
        table_name=write_table_name,
        database_location=dw_db_location,
        layer=LayerEnum.DW.value,
        query=query,
        target_database_name=target_database_name,
        target_database_location=target_database_location,
        # partitions=partitions,
    )
    table_loader_pipeline.run()
