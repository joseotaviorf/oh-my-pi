from argparse import ArgumentParser
from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader

JOB_NAME = "create_lifull_campaigns_raw"

logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source

    database_name = f"datalake_{source}_raw"
    table_name = "campaigns_overview_report"
    table_location = f"s3://{datalake_bucket}/raw/{source}"
    table_schema = OrderedDict(
        [
            ("id", "STRING"),
            ("name", "STRING"),
            ("account_name", "STRING"),
            ("clicks", "STRING"),
            ("desktop_cost", "STRING"),
            ("mobile_cost", "STRING"),
            ("total_cost", "STRING"),
            ("curr_date", "DATE"),
            ("group_name", "STRING"),
        ]
    )

    logger.info(
        f"""m=__main__, environment={env}, source={source},
        datalake_bucket={datalake_bucket},
        msg=Creating table '{database_name}.{table_name}'..."""
    )

    spark_metastore_service = SparkMetastoreService(SparkClient())
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.recreate_table(
        database_name=database_name,
        table_name=table_name,
        new_schema=table_schema,
        s3_path=table_location,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        partitions=["dt"],
    )
