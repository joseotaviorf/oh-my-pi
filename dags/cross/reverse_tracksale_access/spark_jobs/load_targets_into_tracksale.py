import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta
from typing import Optional, Tuple

from quintoandar_logger import QuintoAndarLogger
from quintoandar_tracksale_api_client.clients import TracksaleClient
from quintoandar_tracksale_api_client.requesters import REQUESTERS

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    is_validation_run,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.configuration_service import ConfigurationService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_targets_into_tracksale"
# How long Tracksale keeps the survey open for a response after schedule_time.
DISPATCH_WINDOW_DAYS = 7
# Minimum gap between dispatches of the same campaign to the same customer. Partition grain is
# daily, so one preceding cohort day plus the reference day covers the 24h rule (and same-day
# access re-runs when is_dispatched is still TRUE).
DEDUP_LOOKBACK_DAYS = 1
# While the legacy reverse_tracksale DAG still runs, also suppress emails already dispatched
# there for the same campaign table so forno/prod validation cannot double-hit campaign 297.
LEGACY_DEDUP_DATABASE = "datalake_tracksale_reverse"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
dbutils = BaseDBUtils().get_dbutils()


def parse_arguments() -> Tuple[str, str, str, datetime, Optional[str], Optional[str]]:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name", help="Name of the DAG")
    parser.add_argument("database_name", help="Database where the reverse table is")
    parser.add_argument("table_name", help="Name of the campaign table to be exported")
    parser.add_argument(
        "reference_date", help="Cohort day to be exported, in the format YYYY-MM-DD"
    )

    add_validation_target_args(parser)
    args = parser.parse_args()

    return (
        args.dag_name,
        args.database_name,
        args.table_name,
        datetime.fromisoformat(args.reference_date),
        args.target_database_name,
        args.target_table_name,
    )


def get_campaign(dag_name: str, table_name: str) -> dict:
    """
    Resolve the campaign settings for a table from the environment conf file, so that forno
    dispatches to the test campaign and prod to the real one.
    """
    config_service = ConfigurationService(dag_name)
    campaigns = config_service.get_config("campaigns")

    for campaign in campaigns:
        if campaign["query"] == table_name:
            return campaign

    raise ValueError(
        f"No campaign configured for table_name={table_name}. "
        f"Add it to the `campaigns` key of the conf files."
    )


def get_schedule_window(
    reference_date: datetime, trigger_at_hour: int, trigger_at_minute: int
) -> Tuple[int, int]:
    """
    Build the dispatch window Tracksale should use. When the job runs after the campaign's
    trigger hour there is no time left to dispatch on the reference day, so it goes to the
    next one.
    """
    if datetime.now().hour < trigger_at_hour:
        schedule_date = reference_date
    else:
        schedule_date = reference_date + timedelta(days=1)

    schedule_time = int(
        datetime(
            schedule_date.year,
            schedule_date.month,
            schedule_date.day,
            trigger_at_hour,
            trigger_at_minute,
            0,
        ).timestamp()
    )
    finish_time = int(
        (
            datetime.fromtimestamp(schedule_time) + timedelta(days=DISPATCH_WINDOW_DAYS)
        ).timestamp()
    )

    return schedule_time, finish_time


def get_recently_dispatched_emails(
    database_name: str, table_name: str, reference_date: datetime
) -> set:
    """
    Emails already dispatched for this campaign within the 24h dedup window (reference day and
    the preceding cohort day). Days are listed explicitly so Spark prunes partitions. During the
    migration, also reads the legacy reverse table so a customer already hit by reverse_tracksale
    is not dispatched again from reverse_tracksale_test.
    """
    partition_days = [
        reference_date - timedelta(days=offset)
        for offset in range(0, DEDUP_LOOKBACK_DAYS + 1)
    ]
    partition_predicate = " OR ".join(
        f"(year = {day.year} AND month = {day.month} AND day = {day.day})"
        for day in partition_days
    )

    databases = [database_name]
    if database_name != LEGACY_DEDUP_DATABASE:
        databases.append(LEGACY_DEDUP_DATABASE)

    dispatched_emails = set()
    for source_database in databases:
        try:
            rows = spark.sql(
                f"""
                    SELECT DISTINCT
                        customer_email
                    FROM
                        {source_database}.{table_name}
                    WHERE
                        ({partition_predicate})
                        AND is_dispatched = TRUE
                        AND customer_email IS NOT NULL
                """
            ).collect()
        except Exception as exc:
            logger.warning(
                f"m={JOB_NAME}, database_name={source_database}, table_name={table_name}, "
                f"msg=Skipping dedup source, could not read table: {exc}"
            )
            continue
        dispatched_emails.update(row.customer_email for row in rows)

    return dispatched_emails


def get_pending_rows(
    database_name: str, table_name: str, reference_date: datetime
) -> Tuple[list, set]:
    """
    Cohort of the reference day minus customers already dispatched for this same campaign in the
    last 24h (partition lookback). Suppressed emails must stay flagged as not dispatched on the
    reference partition so a later run can retry them once the window has closed.
    """
    cohort_rows = spark.sql(
        f"""
            SELECT
                *
            FROM
                {database_name}.{table_name}
            WHERE
                year = {reference_date.year}
                AND month = {reference_date.month}
                AND day = {reference_date.day}
                AND is_dispatched = FALSE
                AND customer_email IS NOT NULL
        """
    ).collect()

    dispatched_emails = get_recently_dispatched_emails(
        database_name, table_name, reference_date
    )
    pending_rows = []
    suppressed_emails = set()
    for row in cohort_rows:
        if row.customer_email in dispatched_emails:
            suppressed_emails.add(row.customer_email)
        else:
            pending_rows.append(row)

    return pending_rows, suppressed_emails


def build_payload(rows: list, tags: list, schedule_time: int, finish_time: int) -> dict:
    customers = []
    for row in rows:
        customers.append(
            {
                "name": row.customer_name,
                "email": row.customer_email,
                "phone": row.customer_phone,
                "tags": [
                    {"name": tag["name"], "value": row[tag["value"]]} for tag in tags
                ],
            }
        )

    return {
        "customers": customers,
        "schedule_time": schedule_time,
        "finish_time": finish_time,
    }


def send_targets_to_tracksale(token: str, campaign_code: str, payload: dict):
    tracksale_client = TracksaleClient(api_token=token)
    requester_instance = REQUESTERS["dispatch"](tracksale_client)
    return requester_instance.sync(campaign_code, payload)


def mark_campaign_targets_as_dispatched(
    database_name: str,
    table_name: str,
    reference_date: datetime,
    suppressed_emails: set,
):
    suppressed_clause = ""
    if suppressed_emails:
        email_list = ", ".join(
            "'{}'".format(email.replace("'", "''"))
            for email in sorted(suppressed_emails)
        )
        suppressed_clause = f"AND customer_email NOT IN ({email_list})"

    spark.sql(
        f"""
            UPDATE {database_name}.{table_name}
            SET is_dispatched = TRUE
            WHERE
                year = {reference_date.year}
                AND month = {reference_date.month}
                AND day = {reference_date.day}
                AND is_dispatched = FALSE
                {suppressed_clause}
        """
    )


def main():
    (
        dag_name,
        database_name,
        table_name,
        reference_date,
        target_database_name,
        target_table_name,
    ) = parse_arguments()

    if is_validation_run(target_database_name, target_table_name):
        logger.info(
            f"m={JOB_NAME}, msg=Skipping Tracksale API export in cluster validation mode"
        )
        return

    campaign = get_campaign(dag_name, table_name)
    campaign_code = campaign["campaign_code"]
    tags = json.loads(campaign["tags"])
    schedule_time, finish_time = get_schedule_window(
        reference_date,
        int(campaign["trigger_at_hour"]),
        int(campaign["trigger_at_minute"]),
    )

    logger.info(
        f"""m={JOB_NAME}, database_name={database_name}, table_name={table_name},
        campaign_code={campaign_code}, reference_date={reference_date.date()},
        schedule_time={schedule_time}, finish_time={finish_time}, msg=Starting Spark Job..."""
    )

    rows, suppressed_emails = get_pending_rows(
        database_name, table_name, reference_date
    )
    if suppressed_emails:
        logger.info(
            f"m={JOB_NAME}, table_name={table_name}, "
            f"suppressed_customers={len(suppressed_emails)}, "
            f"lookback_days={DEDUP_LOOKBACK_DAYS}, "
            "msg=Customers skipped, already dispatched for this campaign within 24h."
        )

    if not rows:
        logger.info(
            f"m={JOB_NAME}, table_name={table_name}, msg=No pending targets to dispatch."
        )
        return

    credentials = json.loads(
        dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.TRACKSALE)
    )

    send_targets_to_tracksale(
        credentials["token"],
        campaign_code,
        build_payload(rows, tags, schedule_time, finish_time),
    )

    mark_campaign_targets_as_dispatched(
        database_name, table_name, reference_date, suppressed_emails
    )
    logger.info(
        f"m={JOB_NAME}, table_name={table_name}, dispatched_targets={len(rows)}, "
        "msg=Campaign targets marked as dispatched in datalake reverse."
    )


if __name__ == "__main__":
    main()
