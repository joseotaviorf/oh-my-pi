import logging
import pandas as pd

from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

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

    args = parser.parse_args()

    database_name = args.database_name
    table_name = args.table_name
    s3_path = args.s3_path


    return {
        "database_name": database_name,
        "table_name": table_name,
        "s3_path": s3_path,
    }


def load_table_into_s3(
    database_name: str,
    table_name: str,
    s3_path: str,
):
    """
    Load the table into S3.
    """

    df = spark.table(f"{database_name}.{table_name}")

    logger.info("msg=collect data from table and sending to S3")

    df.toPandas().to_csv(s3_path, index=False)

    logger.info(f"msg=table loaded into S3, path = {s3_path}")

if __name__ == "__main__":
    """
    Start the pipeline.
    """
    job_args_dict = parse_arguments()

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

