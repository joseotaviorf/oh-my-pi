import io
import logging
from argparse import ArgumentParser
from datetime import datetime
from http.client import HTTPException
from urllib.parse import urlparse

import boto3
from dateutil.relativedelta import relativedelta
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.clients.db_clients import SparkClient

JOB_NAME = "load_data_into_xlsx_s3"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("source", help="source name")
    parser.add_argument("query", help="query")
    parser.add_argument("output_path", help="output path value in forno/prod")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    output_path = args.output_path
    source = args.source
    query = args.query
    execution_date = args.execution_date
    dai_reference_date = datetime.strptime(execution_date, "%Y-%m-%d") - relativedelta(
        months=1
    )
    output_path = output_path.format(dai_reference_date.year, dai_reference_date.month)

    logger.info(
        f"m=__main__, environment={environment}, source={source}, output_path={output_path}, "
    )

    spark_client = SparkClient()

    df = spark_client.get_records(query)

    parsed_output_path = urlparse(output_path)
    bucket = parsed_output_path.netloc
    key = parsed_output_path.path.lstrip("/")

    with io.BytesIO() as xlsx_buffer:
        df.toPandas().to_excel(xlsx_buffer, index=False, header=True, engine="openpyxl")

        response = boto3.client("s3").put_object(
            Bucket=bucket,
            Key=key,
            Body=xlsx_buffer.getvalue(),
            ACL="bucket-owner-full-control",
        )

    status = response.get("ResponseMetadata", {}).get("HTTPStatusCode")

    if status == 200:
        logger.info(
            f"m=__main__, message=successful S3 put_object for {source}, status={status}"
        )
    else:
        raise HTTPException(
            f"m=__main__, message=UNSUCCESSFULL S3 put_object for {source}, status={status}"
        )
