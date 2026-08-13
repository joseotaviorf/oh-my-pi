import json
import logging
from argparse import ArgumentParser
from datetime import date, datetime, timedelta
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
# Minimum gap between dispatches of the same campaign to the same customer.
DEDUP_LOOKBACK_HOURS = 24
# Fallback when ts_dispatched is unavailable: look back this many days on partition grain.
PARTITION_DEDUP_LOOKBACK_DAYS = 1

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
dbutils = BaseDBUtils().get_dbutils()


def parse_arguments() -> Tuple[str, str, str, datetime, Optional[str], Optional[str]]:
    """
    Parse CLI arguments passed by the access DAG spark job.

    Returns:
        dag_name: ConfigurationService key (e.g. reverse_tracksale_access).
        database_name: Metastore database that holds the reverse campaign table.
        table_name: Campaign table / query name (e.g. true_seller_ccv_hub).
        reference_date: Partition day (year/month/day) to export (YYYY-MM-DD).
        target_database_name / target_table_name: Optional cluster-validation overrides.
    """
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name", help="Name of the DAG")
    parser.add_argument("database_name", help="Database where the reverse table is")
    parser.add_argument("table_name", help="Name of the campaign table to be exported")
    parser.add_argument(
        "reference_date",
        help="Partition day to be exported, in the format YYYY-MM-DD",
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
    Resolve campaign settings for a reverse table from the environment conf file.

    Forno and prod can point the same table_name at different Tracksale campaign codes
    (e.g. test campaign 242 vs production campaign 297).
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
    schedule_base_date: datetime, trigger_at_hour: int, trigger_at_minute: int
) -> Tuple[int, int]:
    """
    Build Tracksale schedule_time and finish_time (unix timestamps).

    If the job runs before trigger_at_hour, schedule on schedule_base_date; otherwise shift
    to the next calendar day. finish_time is schedule_time plus DISPATCH_WINDOW_DAYS.
    For backfills, callers should pass the execution day as schedule_base_date so the API
    never receives a past window tied to a stale reference_date.
    """
    if datetime.now().hour < trigger_at_hour:
        schedule_date = schedule_base_date
    else:
        schedule_date = schedule_base_date + timedelta(days=1)

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


def ensure_ts_dispatched_column(database_name: str, table_name: str) -> None:
    """
    Ensure the reverse table has ts_dispatched (TIMESTAMP).

    Older partitions created before this column existed still need it for UPDATE and for
    the trailing-24h dedup. No-op when the column is already present.
    """
    full_name = f"{database_name}.{table_name}"
    column_names = {field.name for field in spark.table(full_name).schema.fields}
    if "ts_dispatched" in column_names:
        return

    spark.sql(f"ALTER TABLE {full_name} ADD COLUMNS (ts_dispatched TIMESTAMP)")
    logger.info(
        f"m={JOB_NAME}, table_name={full_name}, "
        "msg=Added missing column ts_dispatched TIMESTAMP."
    )


def get_recently_dispatched_emails_by_timestamp(
    database_name: str, table_name: str, cutoff: datetime
) -> set:
    """
    Return customer emails with ts_dispatched >= cutoff on any table partition.

    This is the primary same-campaign dedup: a customer sent earlier today for another
    reference_date is still suppressed even when that send was written on an older day=.
    """
    cutoff_literal = cutoff.strftime("%Y-%m-%d %H:%M:%S")
    rows = spark.sql(
        f"""
            SELECT DISTINCT
                customer_email
            FROM
                {database_name}.{table_name}
            WHERE
                is_dispatched = TRUE
                AND ts_dispatched IS NOT NULL
                AND ts_dispatched >= TIMESTAMP '{cutoff_literal}'
                AND customer_email IS NOT NULL
        """
    ).collect()
    return {row.customer_email for row in rows}


def get_recently_dispatched_emails_by_partition(
    database_name: str, table_name: str, execution_date: date
) -> set:
    """
    Return emails flagged is_dispatched=TRUE on execution_date and the previous day.

    Used when ts_dispatched is unavailable, as a coarse 24h proxy based on partition grain
    rather than the real POST timestamp.
    """
    partition_days = [
        execution_date - timedelta(days=offset)
        for offset in range(0, PARTITION_DEDUP_LOOKBACK_DAYS + 1)
    ]
    partition_predicate = " OR ".join(
        f"(year = {day.year} AND month = {day.month} AND day = {day.day})"
        for day in partition_days
    )
    rows = spark.sql(
        f"""
            SELECT DISTINCT
                customer_email
            FROM
                {database_name}.{table_name}
            WHERE
                ({partition_predicate})
                AND is_dispatched = TRUE
                AND customer_email IS NOT NULL
        """
    ).collect()
    return {row.customer_email for row in rows}


def get_recently_dispatched_emails(
    database_name: str, table_name: str, execution_date: date
) -> set:
    """
    Build the set of emails that must not receive this campaign again within 24h.

    Prefer ts_dispatched on the reverse database (works across different reprocess
    reference_dates). If that path fails, fall back to partition lookback.
    """
    cutoff = datetime.now() - timedelta(hours=DEDUP_LOOKBACK_HOURS)
    dispatched_emails = set()

    try:
        ensure_ts_dispatched_column(database_name, table_name)
        dispatched_emails.update(
            get_recently_dispatched_emails_by_timestamp(
                database_name, table_name, cutoff
            )
        )
    except Exception as exc:
        logger.warning(
            f"m={JOB_NAME}, database_name={database_name}, table_name={table_name}, "
            f"msg=Falling back to partition dedup on primary table: {exc}"
        )
        dispatched_emails.update(
            get_recently_dispatched_emails_by_partition(
                database_name, table_name, execution_date
            )
        )

    return dispatched_emails


def get_reference_date_rows(
    database_name: str, table_name: str, reference_date: datetime
) -> list:
    """
    Load not-yet-dispatched rows for the reference_date partition.

    Only rows with is_dispatched=FALSE and a non-null customer_email are candidates for
    the Tracksale POST. Re-running the same reference_date after a successful send finds
    an empty set because those rows were marked TRUE.
    """
    return spark.sql(
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


def get_pending_rows(
    database_name: str,
    table_name: str,
    reference_date: datetime,
    execution_date: date,
) -> Tuple[list, set, int]:
    """
    Split the reference_date partition into rows to dispatch vs rows to skip for 24h dedup.

    Returns:
        pending_rows: Rows whose email is not in the last-24h campaign dispatch set.
        suppressed_emails: Emails skipped because they already received this campaign recently.
        pending_before_dedup_count: Size of the is_dispatched=FALSE set before dedup.

    Suppressed emails stay is_dispatched=FALSE on the reference partition so a later run can
    retry them once the 24h window has closed.
    """
    reference_rows = get_reference_date_rows(database_name, table_name, reference_date)
    dispatched_emails = get_recently_dispatched_emails(
        database_name, table_name, execution_date
    )
    pending_rows = []
    suppressed_emails = set()
    for row in reference_rows:
        if row.customer_email in dispatched_emails:
            suppressed_emails.add(row.customer_email)
        else:
            pending_rows.append(row)

    return pending_rows, suppressed_emails, len(reference_rows)


def build_payload(rows: list, tags: list, schedule_time: int, finish_time: int) -> dict:
    """
    Build the Tracksale dispatch payload from pending rows.

    Maps configured tag definitions (display name + source column) onto each customer and
    attaches the schedule / finish window for the campaign.
    """
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
    """POST the customer payload to Tracksale campaign/{campaign_code}/dispatch."""
    tracksale_client = TracksaleClient(api_token=token)
    requester_instance = REQUESTERS["dispatch"](tracksale_client)
    return requester_instance.sync(campaign_code, payload)


def mark_campaign_targets_as_dispatched(
    database_name: str,
    table_name: str,
    reference_date: datetime,
    suppressed_emails: set,
):
    """
    After a successful POST, mark sent rows as dispatched on the reference_date partition.

    Sets is_dispatched=TRUE and ts_dispatched=current_timestamp() for pending rows on that
    partition. Emails in suppressed_emails are excluded so they remain FALSE and can be
    retried after the 24h window.
    """
    ensure_ts_dispatched_column(database_name, table_name)

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
            SET
                is_dispatched = TRUE,
                ts_dispatched = current_timestamp()
            WHERE
                year = {reference_date.year}
                AND month = {reference_date.month}
                AND day = {reference_date.day}
                AND is_dispatched = FALSE
                {suppressed_clause}
        """
    )


def main():
    """
    Export one reverse campaign partition to Tracksale and record the dispatch outcome.

    Guards:
      - Skip entirely when reference_date > CURRENT_DATE (no future-dated dispatch).
      - Skip customers already dispatched for this campaign within the last 24h
        (ts_dispatched preferred; partition proxy as fallback).
      - On backfill (reference_date < CURRENT_DATE), schedule against the execution day and
        warn when customers are skipped for the 24h rule.

    Successful sends update is_dispatched and ts_dispatched on the reference_date partition.
    """
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

    execution_date = date.today()
    reference_day = reference_date.date()
    campaign = get_campaign(dag_name, table_name)
    campaign_code = campaign["campaign_code"]
    tags = json.loads(campaign["tags"])

    logger.info(
        f"m={JOB_NAME}, database_name={database_name}, table_name={table_name}, "
        f"campaign_code={campaign_code}, reference_date={reference_day}, "
        f"execution_date={execution_date}, msg=Starting Spark Job..."
    )

    if reference_day > execution_date:
        logger.warning(
            f"m={JOB_NAME}, table_name={table_name}, reference_date={reference_day}, "
            f"execution_date={execution_date}, dispatched_targets=0, skipped_targets=0, "
            "msg=Skipping dispatch: reference_date is later than the maximum available "
            "data date (CURRENT_DATE / execution_date)."
        )
        return

    # Backfills schedule against the execution day so Tracksale never receives a past window.
    schedule_base_date = (
        datetime.combine(execution_date, datetime.min.time())
        if reference_day < execution_date
        else reference_date
    )
    schedule_time, finish_time = get_schedule_window(
        schedule_base_date,
        int(campaign["trigger_at_hour"]),
        int(campaign["trigger_at_minute"]),
    )

    logger.info(
        f"m={JOB_NAME}, table_name={table_name}, reference_date={reference_day}, "
        f"execution_date={execution_date}, schedule_base_date={schedule_base_date.date()}, "
        f"schedule_time={schedule_time}, finish_time={finish_time}, "
        "msg=Resolved Tracksale schedule window."
    )

    rows, suppressed_emails, pending_before_dedup_count = get_pending_rows(
        database_name, table_name, reference_date, execution_date
    )
    skipped_already_dispatched = len(suppressed_emails)
    dispatched_targets = len(rows)

    if skipped_already_dispatched:
        log_fn = logger.warning if reference_day < execution_date else logger.info
        log_fn(
            f"m={JOB_NAME}, table_name={table_name}, reference_date={reference_day}, "
            f"execution_date={execution_date}, skipped_targets={skipped_already_dispatched}, "
            f"lookback_hours={DEDUP_LOOKBACK_HOURS}, "
            "msg=Skipping customers already dispatched for this campaign within the last 24h."
        )

    if not rows:
        logger.info(
            f"m={JOB_NAME}, table_name={table_name}, reference_date={reference_day}, "
            f"execution_date={execution_date}, "
            f"pending_before_dedup_targets={pending_before_dedup_count}, "
            f"dispatched_targets=0, skipped_targets={skipped_already_dispatched}, "
            "msg=No pending targets to dispatch."
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
        f"m={JOB_NAME}, table_name={table_name}, reference_date={reference_day}, "
        f"execution_date={execution_date}, dispatch_date={execution_date}, "
        f"pending_before_dedup_targets={pending_before_dedup_count}, "
        f"dispatched_targets={dispatched_targets}, "
        f"skipped_targets={skipped_already_dispatched}, "
        "msg=Campaign targets dispatched to Tracksale and marked as is_dispatched=TRUE "
        "with ts_dispatched=current_timestamp() on the reference_date partition."
    )


if __name__ == "__main__":
    main()
