from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DWMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.pipeline.default_row_addition_pipeline import (
    DefaultRowAdditionPipeline,
)

JOB_NAME = "add_default_row_to_dim"

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("dw_bucket")
    parser.add_argument("dw_schema")
    parser.add_argument("layer")
    parser.add_argument("table_name")

    args = parser.parse_args()

    env = args.env
    dw_bucket = args.dw_bucket
    dw_schema = args.dw_schema
    layer = args.layer
    table_name = args.table_name

    logger.info(
        f"m={JOB_NAME}, env={env}, dw_bucket={dw_bucket}, layer={layer}, "
        + f"dw_schema={dw_schema}, table_name={table_name},  msg=Job execution started"
    )

    dw_staging_db_name, dw_staging_db_location = DWMetastoreService.get_layer_info(
        env=env, schema=dw_schema, bucket=dw_bucket, layer=LayerEnum.DW_STAGING.value
    )

    default_row_addition_pipeline = DefaultRowAdditionPipeline(
        database_name=dw_staging_db_name,
        table_name=table_name,
        database_location=dw_staging_db_location,
        layer=layer,
    )
    default_row_addition_pipeline.run()
