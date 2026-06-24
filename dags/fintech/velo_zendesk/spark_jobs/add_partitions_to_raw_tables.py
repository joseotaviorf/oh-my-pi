import logging
from argparse import ArgumentParser

import boto3
from pyspark.sql.functions import lit
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.validation.spark_args import add_validation_target_args
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.storage_services import S3Service

SOURCE = "velo_zendesk"
JOB_NAME = "add_partitions_to_raw_tables"
TABLE_DB_MAPPING = {
    "group_memberships": "velo_zendesk_groups",
    "groups": "velo_zendesk_groups",
    "organizations": "velo_zendesk_groups",
    "satisfaction_ratings": "velo_zendesk_satisfaction",
    "ticket_audits": "velo_zendesk_tickets",
    "ticket_comments": "velo_zendesk_ticket_comments",
    "ticket_fields": "velo_zendesk_ticket_fields",
    "ticket_metrics": "velo_zendesk_tickets",
    "tickets": "velo_zendesk_tickets",
    "users": "velo_zendesk_users",
}

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")
    parser.add_argument("next_execution_date")
    parser.add_argument("table_name")
    add_validation_target_args(parser)
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    table_name = args.table_name

    is_validation_run = (
        args.target_database_name is not None and args.target_table_name is not None
    )

    logger.info(
        f"m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket}, "
        f"execution_date={execution_date}, table_name={table_name}, msg=Starting spark job..."
    )

    spark_client = SparkClient()
    spark = spark_client.conn
    s3_service = S3Service(boto3.resource("s3"))

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    # Stitch lands the daily JSONL under the per-table sub-path; we read only the
    # execution date partition and merge it into the Delta raw table.
    stitch_base = database_location.replace(
        SOURCE, f"{TABLE_DB_MAPPING[table_name]}/{table_name}"
    )
    partition_location = f"{stitch_base}dt={execution_date}"

    if is_validation_run:
        logger.info(
            f"m={JOB_NAME}, msg=Skipping write in validation mode "
            "(Stitch source data remains on prod S3 paths)."
        )
    elif not s3_service.list_objects(partition_location):
        logger.info(
            f"m={JOB_NAME}, partition_location={partition_location}, "
            f"msg=No files found for dt={execution_date}. Skipping."
        )
    else:
        df = spark.read.json(partition_location).withColumn(
            "dt", lit(execution_date).cast("date")
        )

        (
            df.write.format("delta")
            .mode("overwrite")
            .option("replaceWhere", f"dt = '{execution_date}'")
            .option("mergeSchema", "true")
            .partitionBy("dt")
            .saveAsTable(f"{database_name}.{table_name.lower()}")
        )

        logger.info(
            f"m={JOB_NAME}, table={database_name}.{table_name.lower()}, "
            f"dt={execution_date}, msg=Loaded partition into Delta raw table."
        )
