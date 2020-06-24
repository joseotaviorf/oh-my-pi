import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, DWMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.pipeline.load_table_to_redshift_pipeline import (
    LoadTableToRedshiftPipeline,
)

JOB_NAME = "load_table_to_redshift"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument(
        "spectrum_iam_role",
        type=str,
        help="permission for Spectrum to access the table",
    )
    parser.add_argument("dw_bucket", type=str, help="dw bucket")
    parser.add_argument("dw_schema", type=str, help="dw schema")
    parser.add_argument(
        "table_name", type=str, help="table name that will be created in Redshift"
    )

    args = parser.parse_args()
    env = args.env
    spectrum_iam_role = args.spectrum_iam_role
    dw_bucket = args.dw_bucket
    dw_schema = args.dw_schema
    table_name = args.table_name

    logger.info(
        f"m={JOB_NAME}, env={env}, spectrum_iam_role={spectrum_iam_role}, dw_bucket={dw_bucket}, "
        + f"dw_schema={dw_schema}, table_name={table_name}, msg=Job execution started"
    )

    schema_database_name, schema_database_location = DWMetastoreService.get_layer_info(
        env, dw_schema, dw_bucket, "schema"
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    redshift_connection = json.loads(
        dbutils.secrets.get("quintoandar", DatabaseEnum.DW)
    )

    load_table_to_redshift_pipeline = LoadTableToRedshiftPipeline(
        spectrum_iam_role,
        redshift_connection,
        dw_bucket,
        dw_schema,
        schema_database_name,
        table_name,
    )
    load_table_to_redshift_pipeline.run()
