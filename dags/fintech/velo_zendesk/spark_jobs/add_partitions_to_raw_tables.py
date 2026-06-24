import logging
from argparse import ArgumentParser

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.validation.spark_args import add_validation_target_args
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.metastore_services import SparkMetastoreService
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
    next_execution_date = args.next_execution_date
    table_name = args.table_name
    partition_cols = [{"dt": execution_date}, {"dt": next_execution_date}]

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket},
            execution_date={execution_date}, msg=Starting spark job...
        """
    )

    spark_client = SparkClient()
    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    s3_service = S3Service(boto3.resource("s3"))

    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    is_validation_run = (
        args.target_database_name is not None and args.target_table_name is not None
    )

    # Stitch loads data to prod S3; this job only registers metastore partitions.
    for level in partition_cols:
        partition_location = database_location.replace(
            SOURCE, f"{TABLE_DB_MAPPING[table_name]}/{table_name}"
        )
        for column, value in level.items():
            partition_location += "".join(f"{column}={value}")

        if s3_service.list_objects(partition_location):
            if is_validation_run:
                logger.info(
                    f"m={JOB_NAME}, msg=Skipping metastore partition registration in "
                    "validation mode (Stitch data remains on prod S3 paths)"
                )
            else:
                metastore_service.add_partitions(
                    database_name, table_name.lower(), partition_cols
                )
