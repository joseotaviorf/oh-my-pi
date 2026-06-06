import logging
from argparse import ArgumentParser
from http.client import HTTPException
from io import StringIO

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    is_validation_run,
)
from bietlejuice.services.storage_services import S3Service

JOB_NAME = "load_into_s3"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments() -> dict:
    """
    Parse the arguments passed to the job.
    """

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")
    parser.add_argument("s3_path", help="The path of S3 to load data")

    add_validation_target_args(parser)
    args = parser.parse_args()

    return {
        "database_name": args.database_name,
        "table_name": args.table_name,
        "s3_path": args.s3_path,
        "target_database_name": args.target_database_name,
        "target_table_name": args.target_table_name,
    }


def load_table_into_s3(
    database_name: str,
    table_name: str,
    s3_path: str,
):
    """
    Load the table into S3.
    """
    s3_service = S3Service(boto3.resource("s3"))
    csv_buffer = StringIO()

    df = spark.table(f"{database_name}.{table_name}")

    logger.info("msg=collect data from table and sending to S3")

    df.toPandas().to_csv(csv_buffer, index=False)

    file = csv_buffer.getvalue()

    logger.info(f"msg=table loaded into S3, path = {s3_path}")

    try:
        s3_service.upload_file(file, s3_path)

        logger.info(
            f"m=__main__, message=successful S3 put_object for table {table_name}"
        )

    except Exception as e:
        raise HTTPException(
            f"m=__main__, message=UNSUCCESSFULL S3 put_object for table {table_name}, error={e}"
        )


if __name__ == "__main__":
    """
    Start the pipeline.
    """
    job_args_dict = parse_arguments()

    if is_validation_run(
        job_args_dict["target_database_name"],
        job_args_dict["target_table_name"],
    ):
        logger.info(
            f"m={JOB_NAME}, msg=Skipping reverse S3 export in cluster validation mode"
        )
    else:
        logger.info(
            f"""m=__main__, 
                database_name={job_args_dict["database_name"]}, 
                table_name={job_args_dict["table_name"]}, 
                s3_path={job_args_dict["s3_path"]}"""
        )

        load_table_into_s3(
            database_name=job_args_dict["database_name"],
            table_name=job_args_dict["table_name"],
            s3_path=job_args_dict["s3_path"],
        )
