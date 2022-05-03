import logging
from argparse import ArgumentParser
from datetime import datetime
from dateutil.relativedelta import relativedelta

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.s3_consumer import S3Consumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_data_into_xlsx_s3"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("source", help="source name")
    parser.add_argument("query", help="query")
    parser.add_argument("output_path", help="output path value in forno/prod")
    parser.add_argument("format_options", help="format_options for s3_loader")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    output_path = args.output_path
    source = args.source
    query = args.query
    format_options = args.format_options
    execution_date = args.execution_date
    dai_reference_date = datetime.strptime(execution_date, "%Y-%m-%d") - relativedelta(
        months=1
    )
    output_path = output_path.format(dai_reference_date.year, dai_reference_date.month)

    logger.info(
        f"m=__main__, environment={environment}, source={source}, output_path={output_path}, "
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    df = spark_client.get_records(query)

    df = SparkDataFrameService().input(df).output()

    s3_loader = S3Loader()

    s3_loader.load_df(
        df=df, s3_path=output_path, format_options=format_options, header="true"
    )
