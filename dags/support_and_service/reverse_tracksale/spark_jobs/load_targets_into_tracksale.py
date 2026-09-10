import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta

from pyspark.sql.functions import col, lit, when
from quintoandar_logger import QuintoAndarLogger
from quintoandar_tracksale_api_client.clients import TracksaleClient
from quintoandar_tracksale_api_client.requesters import REQUESTERS

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_targets_into_tracksale"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def create_tags_dict():
    tags_dict = []
    for tag in tags:
        tag_value = tag.get("value")
        tags_dict.append({"name": tag.get("name"), "value": row[tag_value]})
    return tags_dict


def send_targets_to_tracksale(token, campaign_code, payload):
    tracksale_client = TracksaleClient(api_token=token)
    requester_instance = REQUESTERS["dispatch"](tracksale_client)
    send_data = requester_instance.sync(campaign_code, payload)
    return send_data


def mark_campaign_targets_as_dispatched(full_df, partition_path):
    updated_df = full_df.withColumn(
        "is_dispatched",
        when(col("is_dispatched") == lit(False), lit(True)).otherwise(
            col("is_dispatched")
        ),
    )
    try:
        updated_df.write.mode("overwrite").format(
            SparkTableStorageFormat.DEFAULT_DW
        ).save(partition_path)
    except Exception as e:
        logger.error(
            f"m=Error marking campaign targets as dispatched, message_error={e}, partition_path={partition_path}"
        )
        raise e


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="source name")
    parser.add_argument("campaign_code", help="source name")
    parser.add_argument("campaign_query", help="campaign query")
    parser.add_argument("tags", help="campaign tags")
    parser.add_argument(
        "trigger_at_hour", help="hour that the campaign should be triggered"
    )
    parser.add_argument(
        "trigger_at_minute", help="minute that the campaign should be triggered"
    )
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    campaign_code = args.campaign_code
    campaign_query = args.campaign_query
    tags = args.tags
    trigger_at_hour = args.trigger_at_hour
    trigger_at_minute = args.trigger_at_minute
    execution_date = args.execution_date

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        campaign_code={campaign_code}, campaign_query={campaign_query}, tags={tags},
        trigger_at_hour={trigger_at_hour}, trigger_at_minute={trigger_at_minute}, execution_date={execution_date},
        msg=Starting Spark Job..."""
    )

    execution_date = datetime.strptime(execution_date, "%Y-%m-%d") + timedelta(days=1)

    if datetime.now().hour < 17:
        schedule_date = execution_date
    else:
        schedule_date = execution_date + timedelta(days=1)

    schedule_time = int(
        datetime(
            schedule_date.year,
            schedule_date.month,
            schedule_date.day,
            int(trigger_at_hour),
            int(trigger_at_minute),
            0,
        ).timestamp()
    )
    end_time = int(
        (datetime.fromtimestamp(schedule_time) + timedelta(days=7)).timestamp()
    )

    path = f"{datalake_bucket}/{campaign_query}/year={execution_date.year}/month={execution_date.month}/day={execution_date.day}/"

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    try:
        full_df = s3_consumer.get_data_from_file(path=path, format="parquet").cache()
        pending_rows = full_df.filter(col("is_dispatched") == lit(False)).collect()
    except Exception as e:
        logger.error(f"m=There's no data here yet, message_error={e}")
        full_df = None
        pending_rows = []

    if len(pending_rows) > 0:
        tags = json.loads(tags)

        payload = {
            "customers": [],
            "schedule_time": schedule_time,
            "finish_time": end_time,
        }
        for row in pending_rows:
            payload["customers"].append(
                {
                    "name": row.customer_name,
                    "email": row.customer_email,
                    "phone": row.customer_phone,
                    "tags": create_tags_dict(),
                }
            )

        base_dbutils = BaseDBUtils()
        if base_dbutils.get_dbutils() is not None:
            dbutils = base_dbutils.get_dbutils()

        json_credentials = dbutils.secrets.get(
            scope=DATABRICKS_SCOPE, key=APIEnum.TRACKSALE
        )
        credentials = json.loads(json_credentials)

        send_targets_to_tracksale(credentials["token"], campaign_code, payload)

        mark_campaign_targets_as_dispatched(full_df, path)
        logger.info(
            f"m={JOB_NAME}, campaign_query={campaign_query}, path={path}, "
            "msg=Campaign targets marked as dispatched in datalake reverse."
        )

    else:
        pass
