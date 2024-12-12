import logging
import json
from argparse import ArgumentParser
from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger

from quintoandar_tracksale_api_client.clients import TracksaleClient
from quintoandar_tracksale_api_client.requesters import REQUESTERS

from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import BaseDBUtils

from bietlejuice.services.configuration_service import ConfigurationService

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

def get_parameters(campaigns, table_name):
    for campaign in campaigns["campaigns"]:
        if campaign["query"] == table_name:
            campaign_code = campaign["campaign_code"]
            tags = campaign["tags"]
            trigger_at_hour = campaign["trigger_at_hour"]
            trigger_at_minute = campaign["trigger_at_minute"]
            return campaign_code, tags, trigger_at_hour, trigger_at_minute

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="source name")
    parser.add_argument("dag_name", help="dag_name")
    parser.add_argument("table_name", help="Table name")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    dag_name = args.dag_name
    table_name = args.table_name

    config_service = ConfigurationService(dag_name)
    campaigns = config_service.get_config("campaigns")

    campaign_code, tags, trigger_at_hour, trigger_at_minute = get_parameters(campaigns, table_name)
    execution_date = args.execution_date

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, dag_name={dag_name}, datalake_bucket={datalake_bucket},
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
            schedule_date.year, schedule_date.month, schedule_date.day, int(trigger_at_hour), int(trigger_at_minute), 0
        ).timestamp()
    )
    end_time = int(
        (datetime.fromtimestamp(schedule_time) + timedelta(days=7)).timestamp()
    )

    path = f"{datalake_bucket}/{campaign_query}/year={execution_date.year}/month={execution_date.month}/day={execution_date.day}/"

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    try:
        df = (
            s3_consumer.get_data_from_file(path=path, format="parquet")
            .filter("is_dispatched = false")
            .collect()
        )
    except Exception as e:
        logger.error("m=There's no data here yet, message_error={}".format(e))
        df = []

    if len(df) > 0:

        tags = json.loads(tags)

        payload = {
            "customers": [],
            "schedule_time": schedule_time,
            "finish_time": end_time,
        }
        for row in df:
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

        api_response = send_targets_to_tracksale(
            credentials["token"], campaign_code, payload
        )

    else:
        pass