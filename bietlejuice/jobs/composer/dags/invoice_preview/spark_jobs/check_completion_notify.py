from argparse import ArgumentParser
from datetime import datetime
import logging

from quintoandar_logger import QuintoAndarLogger

from inmetro.messengers import SlackMessenger
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum


def create_message(environment, database_name, table_name, count_result):

    message = (
        f":warning:\n"
        f"Validation: `{database_name}.{table_name}`\n"
        f"Environment: *{environment}*\n"
        f"Status: *FAILED*\n\n"
        f"*Count validation failed for `{datetime.now().strftime('%Y-%m-%d')} execution_date`\n"
        f"*Count result: `{count_result}`\n"
    )

    return message


JOB_NAME = "check_completion_notify"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("table_name", help="name of table to check")
    parser.add_argument("execution_date", help="execution date")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date = args.execution_date

    logger.info(
        f"""
                m=__main__, environment={environment}, datalake_bucket={datalake_bucket}, source={source},
                table_name={table_name}, execution_date={execution_date}, msg=Starting spark job...
        """
    )

    # Retrieving folders/tables from root location.
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    spark_client = SparkClient()
    year, month, day = execution_date.split("-")
    database_name = f"datalake_{source}_raw"

    filter_condition = f"WHERE year={year} AND month={month} AND day={day}"
    query_template = f"""SELECT COUNT(*) as count FROM {database_name}.{table_name} {filter_condition}"""
    df = spark_client.get_records(query_template)

    result = df.first().asDict()["count"]

    # #################################### Slack Alert ######################################

    if result == 0:

        logger.info(
            f"""
                m=__main__, msg=Count validation result is 0...
        """
        )

        slack_webhook = dbutils.secrets.get(
            scope="quintoandar", key=APIEnum.AIRFLOW_ALERTS_INMETRO_SLACK_WEBHOOK
        )

        messenger = SlackMessenger(slack_webhook)
        message = create_message(environment, database_name, table_name, result)
        if messenger.send_message(message) is not True:
            raise ValueError(
                "m=__main__, msg=Could not send slack message, check logs."
            )
