import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DWMetastoreService
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.pipeline import FullTableLoaderPipeline

JOB_NAME = "load_full_table_to_dw_final_schema"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("dw_bucket", type=str, help="dw bucket")
    parser.add_argument("dw_schema", type=str, help="dw schema")
    parser.add_argument("table_name", type=str, help="table name that will be created")

    args = parser.parse_args()

    env = args.env
    dw_bucket = args.dw_bucket
    dw_schema = args.dw_schema
    table_name = args.table_name

    logger.info(
        f"m={JOB_NAME}, env={env}, dw_bucket={dw_bucket}, dw_schema={dw_schema}, table_name={table_name}, "
        + "msg=Job execution started"
    )

    schema_database_name, schema_database_location = DWMetastoreService.get_layer_info(
        env, dw_schema, dw_bucket, "schema"
    )

    (
        database_name_staging,
        database_location_staging,
    ) = DWMetastoreService.get_layer_info(env, dw_schema, dw_bucket, "staging")

    query = f"SELECT * FROM {database_name_staging}.{table_name}"

    table_loader_pipeline = FullTableLoaderPipeline(
        schema_database_name,
        table_name,
        schema_database_location,
        LayerEnum.DW.value,
        query,
    )
    table_loader_pipeline.run()
