import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DWMetastoreService
from bietlejuice.jobs.composer.pipeline.default_row_addition_pipeline import (
    DefaultRowAdditionPipeline,
)

JOB_NAME = "add_default_row_to_dim"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno or prod values")
    parser.add_argument("dw_bucket", type=str, help="dw bucket")
    parser.add_argument("dw_schema", type=str, help="dw schema")
    parser.add_argument("layer", type=str, help="layer to save data to")
    parser.add_argument(
        "table_name", type=str, help="table name that will be processed"
    )

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

    schema_database_name, schema_database_location = DWMetastoreService.get_layer_info(
        env, dw_schema, dw_bucket, "staging"
    )

    default_row_addition_pipeline = DefaultRowAdditionPipeline(
        schema_database_name, table_name, schema_database_location, layer
    )
    default_row_addition_pipeline.run()
