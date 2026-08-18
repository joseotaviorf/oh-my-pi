import json
import logging
import time
from argparse import ArgumentParser
from datetime import date, datetime, timedelta, timezone
from typing import List, Optional, Tuple

from pyspark.sql.types import (
    BooleanType,
    IntegerType,
    StringType,
    StructField,
    StructType,
)
from quintoandar_logger import QuintoAndarLogger
from quintoandar_tracksale_api_client.clients import TracksaleClient
from quintoandar_tracksale_api_client.requesters import REQUESTERS
from requests import RequestException

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.base.sst.domains.salesforce.api.api_logs import (
    LOGS_TARGET_TABLE,
    TRACKSALE_SERVICE_NAME,
    conform_and_save_tracksale_api_logs,
)
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
# Attempts to mark the dispatched targets before giving up (1 initial + 2 retries).
MARK_DISPATCH_MAX_ATTEMPTS = 3
# Linear backoff between marking attempts, to let a competing Delta writer finish.
MARK_DISPATCH_RETRY_WAIT_SECONDS = 10

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


TRACKSALE_API_LOG_SCHEMA = StructType(
    [
        StructField("id_record", StringType(), True),
        StructField("idx", IntegerType(), True),
        StructField("status_code", IntegerType(), True),
        StructField("api_logs", StringType(), True),
        StructField("success", BooleanType(), True),
        StructField("error", StringType(), True),
    ]
)


def build_tracksale_api_log_rows(
    dispatch_result: dict, error: Optional[Exception] = None
) -> List[dict]:
    """Build one log row per Tracksale dispatch chunk response.

    ``error`` describes a failure that happened *after* Tracksale accepted the
    payload (the is_dispatched marking). The chunk payload is kept so the
    counters and dispatch codes survive for forensics, while success is recorded
    as False because the dispatch as a whole did not complete.
    """
    rows = []
    for idx, chunk in enumerate(dispatch_result.get("chunks") or []):
        rows.append(
            {
                "id_record": chunk.get("dispatch_code"),
                "idx": idx,
                "status_code": 200,
                "api_logs": json.dumps(chunk),
                "success": error is None,
                "error": None if error is None else str(error),
            }
        )
    return rows


def build_tracksale_api_error_row(error: Exception) -> dict:
    """Build a single failure row when the Tracksale API call raises."""
    status_code = None
    response = getattr(error, "response", None)
    if response is not None:
        status_code = response.status_code

    return {
        "id_record": None,
        "idx": 0,
        "status_code": status_code,
        "api_logs": None,
        "success": False,
        "error": str(error),
    }


def save_tracksale_api_logs(
    log_rows: List[dict],
    api_entity: str,
    target_table: str,
    job_name: str,
    partition_date: str,
    bucket: str,
):
    """Persist Tracksale API responses to datalake_sst_metrics.api_logs.

    Never raises: observability must not fail a task whose targets were already
    dispatched, since a retry would re-send the same customers to Tracksale.
    """
    if not log_rows:
        return

    try:
        logs_df = spark.createDataFrame(log_rows, schema=TRACKSALE_API_LOG_SCHEMA)
        conform_and_save_tracksale_api_logs(
            spark=spark,
            df=logs_df,
            api_entity=api_entity,
            target_table=target_table,
            job_name=job_name,
            partition_date=partition_date,
            bucket=bucket,
        )
    except Exception:
        logger.exception(
            f"m={JOB_NAME}, target_table={target_table}, "
            "msg=Failed to persist Tracksale API logs."
        )


def get_accepted_dispatch_chunk_logs(
    campaign_code: str,
    target_table: str,
    job_name: str,
    partition_date: str,
) -> List[str]:
    """
    Read the chunk payloads Tracksale already answered with HTTP 200 for this partition.

    A row logged with status_code 200 proves Tracksale accepted the customers, even when
    success is False because the run failed to mark them afterwards. Rows are restricted to
    the DEDUP_LOOKBACK_HOURS window, matching the dedup applied on the campaign table.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(hours=DEDUP_LOOKBACK_HOURS)
    cutoff_literal = cutoff.strftime("%Y-%m-%d %H:%M:%S")
    rows = spark.sql(
        f"""
            SELECT
                api_logs
            FROM
                {LOGS_TARGET_TABLE}
            WHERE
                partition_date = '{partition_date}'
                AND entity_type = '{campaign_code}'
                AND job_name = '{job_name}'
                AND service_name = '{TRACKSALE_SERVICE_NAME}'
                AND target_table = '{target_table}'
                AND status_code = 200
                AND api_logs IS NOT NULL
                AND TO_TIMESTAMP(load_ts) >= TIMESTAMP '{cutoff_literal}'
            ORDER BY
                query_idx
        """
    ).collect()
    return [row.api_logs for row in rows]


def rebuild_dispatch_result(chunk_logs: List[str]) -> Optional[dict]:
    """
    Rebuild a dispatch result from logged chunk payloads, as the client would return it.

    Returning the same shape lets the caller reuse the regular logging and counter code on
    the recovery path. Unparseable payloads are dropped; None means nothing usable was
    logged, so there is no accepted dispatch to reuse.
    """
    chunks = []
    for chunk_log in chunk_logs:
        try:
            chunks.append(json.loads(chunk_log))
        except (TypeError, ValueError):
            logger.warning(
                f"m={JOB_NAME}, msg=Ignoring unparseable api_logs chunk payload."
            )

    if not chunks:
        return None

    totals = {"inserted": 0, "invalid": 0, "duplicated": 0}
    for chunk in chunks:
        status = chunk.get("status") or {}
        for counter in totals:
            totals[counter] += int(status.get(counter) or 0)

    return {"status": totals, "chunks": chunks}


def get_previously_accepted_dispatch(
    campaign_code: str,
    target_table: str,
    job_name: str,
    partition_date: str,
) -> Optional[dict]:
    """
    Return the dispatch Tracksale already accepted for this partition, or None.

    An Airflow task retry re-runs this job from scratch. When the previous attempt POSTed
    successfully but failed to mark the targets, they are still is_dispatched=FALSE with a
    null ts_dispatched, so neither dedup path on the campaign table suppresses them and the
    retry would send the same customers twice. api_logs is the only record of that POST.

    Degrades to None when the log cannot be read: api_logs does not exist before the first
    dispatch of an environment, and observability must not block the daily run. The marking
    on the campaign table therefore remains the primary dedup guard.
    """
    try:
        chunk_logs = get_accepted_dispatch_chunk_logs(
            campaign_code, target_table, job_name, partition_date
        )
    except Exception as exc:
        logger.warning(
            f"m={JOB_NAME}, target_table={target_table}, "
            f"msg=Could not read {LOGS_TARGET_TABLE} to look for an accepted dispatch, "
            f"proceeding with the POST: {exc}"
        )
        return None

    return rebuild_dispatch_result(chunk_logs)


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


def mark_campaign_targets_as_dispatched_with_retry(
    database_name: str,
    table_name: str,
    reference_date: datetime,
    suppressed_emails: set,
):
    """Mark the dispatched targets, retrying before giving up.

    Losing this marking is expensive: Tracksale already accepted the payload, so
    the next run would re-send the same customers as duplicate surveys. The
    UPDATE only touches ``is_dispatched = FALSE`` rows, so it is idempotent and a
    retry can never mark anything twice — which makes retrying the transient
    failures here (typically a competing Delta writer on the partition) safe.

    Raises the last error once MARK_DISPATCH_MAX_ATTEMPTS is exhausted.
    """
    for attempt in range(1, MARK_DISPATCH_MAX_ATTEMPTS + 1):
        try:
            mark_campaign_targets_as_dispatched(
                database_name, table_name, reference_date, suppressed_emails
            )
        except Exception as error:
            if attempt == MARK_DISPATCH_MAX_ATTEMPTS:
                logger.error(
                    f"m={JOB_NAME}, table_name={table_name}, "
                    f"attempts={attempt}, error={error}, "
                    "msg=Giving up on marking dispatched targets. Targets stay "
                    "is_dispatched=FALSE and the next run will re-send them."
                )
                raise

            wait_seconds = MARK_DISPATCH_RETRY_WAIT_SECONDS * attempt
            logger.warning(
                f"m={JOB_NAME}, table_name={table_name}, "
                f"attempt={attempt}/{MARK_DISPATCH_MAX_ATTEMPTS}, "
                f"error={error}, retry_in_seconds={wait_seconds}, "
                "msg=Failed to mark dispatched targets; retrying."
            )
            time.sleep(wait_seconds)
        else:
            if attempt > 1:
                logger.info(
                    f"m={JOB_NAME}, table_name={table_name}, attempts={attempt}, "
                    "msg=Marked dispatched targets after retrying."
                )
            return


def main():
    """
    Export one reverse campaign partition to Tracksale and record the dispatch outcome.

    Guards:
      - Skip entirely when reference_date > CURRENT_DATE (no future-dated dispatch).
      - Skip customers already dispatched for this campaign within the last 24h
        (ts_dispatched preferred; partition proxy as fallback).
      - Skip the POST altogether when api_logs already holds an accepted dispatch for this
        partition, so an Airflow task retry recovers the marking instead of re-sending.
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

    config_service = ConfigurationService(dag_name)
    datalake_bucket = config_service.get_config("datalake_bucket")
    job_name = f"{dag_name}.{JOB_NAME}"
    target_table = f"{database_name}.{table_name}"
    partition_date = reference_day.isoformat()

    dispatch_result = get_previously_accepted_dispatch(
        str(campaign_code), target_table, job_name, partition_date
    )
    reused_accepted_dispatch = dispatch_result is not None

    if reused_accepted_dispatch:
        logger.warning(
            f"m={JOB_NAME}, table_name={table_name}, reference_date={reference_day}, "
            f"execution_date={execution_date}, "
            f"lookback_hours={DEDUP_LOOKBACK_HOURS}, "
            "msg=Tracksale already accepted this partition's payload on an earlier attempt "
            "that failed to mark the targets. Skipping the POST and retrying the marking "
            "so the customers are not sent twice."
        )
    else:
        try:
            dispatch_result = send_targets_to_tracksale(
                credentials["token"],
                campaign_code,
                build_payload(rows, tags, schedule_time, finish_time),
            )
        except RequestException as error:
            save_tracksale_api_logs(
                log_rows=[build_tracksale_api_error_row(error)],
                api_entity=str(campaign_code),
                target_table=target_table,
                job_name=job_name,
                partition_date=partition_date,
                bucket=datalake_bucket,
            )
            raise

    # Tracksale has accepted the payload by this point, either now or on the attempt
    # this run is recovering from, so mark the targets before doing any further work:
    # anything that fails while they are still unmarked lets a retry re-send the same
    # customers and duplicate their surveys.
    try:
        mark_campaign_targets_as_dispatched_with_retry(
            database_name, table_name, reference_date, suppressed_emails
        )
    except Exception as marking_error:
        error_rows = build_tracksale_api_log_rows(dispatch_result, error=marking_error)
        if not error_rows:
            # No chunk to attach the error to; still record that it happened.
            error_rows = [build_tracksale_api_error_row(marking_error)]

        save_tracksale_api_logs(
            log_rows=error_rows,
            api_entity=str(campaign_code),
            target_table=target_table,
            job_name=job_name,
            partition_date=partition_date,
            bucket=datalake_bucket,
        )
        raise

    save_tracksale_api_logs(
        log_rows=build_tracksale_api_log_rows(dispatch_result),
        api_entity=str(campaign_code),
        target_table=target_table,
        job_name=job_name,
        partition_date=partition_date,
        bucket=datalake_bucket,
    )

    dispatch_status = dispatch_result.get("status") or {}
    inserted = dispatch_status.get("inserted", 0)
    invalid = dispatch_status.get("invalid", 0)
    duplicated = dispatch_status.get("duplicated", 0)

    logger.info(
        f"m={JOB_NAME}, table_name={table_name}, reference_date={reference_day}, "
        f"execution_date={execution_date}, dispatch_date={execution_date}, "
        f"pending_before_dedup_targets={pending_before_dedup_count}, "
        f"dispatched_targets={dispatched_targets}, "
        f"skipped_targets={skipped_already_dispatched}, "
        f"inserted={inserted}, invalid={invalid}, duplicated={duplicated}, "
        f"reused_accepted_dispatch={reused_accepted_dispatch}, "
        "msg=Campaign targets dispatched to Tracksale and marked as is_dispatched=TRUE "
        "with ts_dispatched=current_timestamp() on the reference_date partition. Counters "
        "come from the earlier accepted dispatch when reused_accepted_dispatch is True."
    )


if __name__ == "__main__":
    main()
