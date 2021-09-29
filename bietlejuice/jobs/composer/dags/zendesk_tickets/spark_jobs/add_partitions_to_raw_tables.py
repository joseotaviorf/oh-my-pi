import boto3
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services import S3Service

SOURCE = "zendesk"
NEW_SOURCE_NAME = "zendesk_tickets"
JOB_NAME = "add_partitions_to_raw_tables"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    partition_cols = [{"dt": execution_date}]
    TABLE_DB_MAPPING = {
        "group_memberships": "zendesk_tickets",
        "groups": "zendesk_groups",
        "organizations": "zendesk_groups",
        "satisfaction_ratings": "zendesk_satisfaction",
        "ticket_fields": "zendesk_ticket_fields",
        "ticket_metrics": "zendesk_tickets",
        "tickets": "zendesk_tickets",
        "users": "zendesk_users",
    }

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
    database_name = database_name.replace(SOURCE, NEW_SOURCE_NAME)
    database_location = db_info["db_raw_path"]

    tables_list = TABLE_DB_MAPPING.keys()
    # as Stitch loads the data, we just add partition here
    for table in tables_list:
        partition_location = database_location.replace(
            SOURCE, f"{TABLE_DB_MAPPING[table]}/{table}"
        )
        partitions = []
        for level in partition_cols:
            for column, value in level.items():
                partitions.append(f"{column}={value}")
        partition_location += "/".join(partitions)

        if s3_service.list_objects(partition_location):
            metastore_service.add_partitions(
                database_name, table.lower(), partition_cols
            )
