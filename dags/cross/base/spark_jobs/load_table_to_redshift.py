import json
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum, DWMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.pipeline.load_table_to_redshift_pipeline import (
    LoadTableToRedshiftPipeline,
)

JOB_NAME = "load_table_to_redshift"

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("spectrum_iam_role")
    parser.add_argument("dw_bucket")
    parser.add_argument("dw_schema")
    parser.add_argument("table_name")

    args = parser.parse_args()
    env = args.env
    spectrum_iam_role = args.spectrum_iam_role
    dw_bucket = args.dw_bucket
    dw_schema = args.dw_schema
    table_name = args.table_name

    logger.info(
        f"m={JOB_NAME}, env={env}, spectrum_iam_role={spectrum_iam_role}, "
        f"dw_bucket={dw_bucket}, dw_schema={dw_schema}, table_name={table_name}, "
        "msg=Job execution started"
    )

    dw_db_name, _ = DWMetastoreService.get_layer_info(
        env=env, schema=dw_schema, bucket=dw_bucket, layer=LayerEnum.DW.value
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    redshift_connection = json.loads(
        dbutils.secrets.get("quintoandar", DatabaseEnum.DW)
    )

    load_table_to_redshift_pipeline = LoadTableToRedshiftPipeline(
        spectrum_iam_role=spectrum_iam_role,
        redshift_connection=redshift_connection,
        dw_bucket=dw_bucket,
        dw_schema=dw_schema,
        source_schema=dw_db_name,
        table_name=table_name,
    )
    load_table_to_redshift_pipeline.run()
