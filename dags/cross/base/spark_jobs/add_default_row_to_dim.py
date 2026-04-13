from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DWMetastoreService
from bietlejuice.base.spark.runtime_detector import RuntimeDetector
from bietlejuice.pipeline.default_row_addition_pipeline import (
    DefaultRowAdditionPipeline,
)
from bietlejuice.pipeline.delta_default_row_addition_pipeline import (
    DeltaDefaultRowAdditionPipeline,
)

JOB_NAME = "add_default_row_to_dim"

logger = QuintoAndarLogger(JOB_NAME)


def main():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("dw_bucket")
    parser.add_argument("dw_schema")
    parser.add_argument("layer")
    parser.add_argument("table_name")
    parser.add_argument(
        "--delta",
        nargs="?",
        dest="is_delta_table",
        required=False,
        default=False,
        const=True,
        help="Whether the table is a Delta table",
    )

    args = parser.parse_args()

    global spark
    if RuntimeDetector.is_emr():
        from bietlejuice.base.spark.spark_session_factory import create_emr_spark_session

        spark = create_emr_spark_session(JOB_NAME)

    logger.info(
        f"m={JOB_NAME}, env={args.env}, dw_bucket={args.dw_bucket}, layer={args.layer}, "
        + f"dw_schema={args.dw_schema}, table_name={args.table_name},  msg=Job execution started"
    )

    database_name, database_location = DWMetastoreService.get_layer_info(
        env=args.env, schema=args.dw_schema, bucket=args.dw_bucket, layer=args.layer
    )

    if args.is_delta_table:
        default_row_addition_pipeline = DeltaDefaultRowAdditionPipeline(
            database_name=database_name,
            table_name=args.table_name,
            database_location=database_location,
            spark=spark,
        )
    else:
        default_row_addition_pipeline = DefaultRowAdditionPipeline(
            database_name=database_name,
            table_name=args.table_name,
            database_location=database_location,
            layer=args.layer,
        )
    default_row_addition_pipeline.run()


if __name__ == "__main__":
    try:
        main()
    finally:
        try:
            if RuntimeDetector.is_emr():
                spark.stop()
        except NameError:
            pass
