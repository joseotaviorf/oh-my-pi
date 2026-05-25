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

    query = f"SELECT * FROM {dw_staging_db_name}.{table_name}"

    table_loader_pipeline = FullTableLoaderPipeline(
        database_name=dw_db_name,
        table_name=table_name,
        database_location=dw_db_location,
        layer=LayerEnum.DW.value,
        query=query,
        # partitions=partitions,
    )
    table_loader_pipeline.run()
