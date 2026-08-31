"""Salesforce CDC dead-letter (DLQ) replay pipeline.

Finds ``id_record`` values present in raw but missing from clean for a
partition, re-fetches them from the Salesforce API as ``RECOVERY`` events,
upserts them into raw, then replays the full raw history for those IDs
through in-memory CDC into the clean table.

Entry point name: ``salesforce/dlq``.
"""

from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.configs.salesforce import SUBJECT_ENDPOINT
from bietlejuice.base.sst.core.api.request import get_request
from bietlejuice.base.sst.core.utils.common import (
    default_args,
    normalize_df_columns,
    retrieve_spark_session,
    validate_and_upsert,
)
from bietlejuice.base.sst.core.utils.time import standard_now
from bietlejuice.base.sst.core.utils.transforms import apply_schema_remaps
from bietlejuice.base.sst.domains.core.events import retrieve_missing_events
from bietlejuice.base.sst.domains.salesforce.api.calls import (
    build_query_chunks,
    retrieve_salesforce_event,
)
from bietlejuice.base.sst.domains.salesforce.api.credentials import retrieve_token
from bietlejuice.base.sst.domains.salesforce.api.headers import (
    build_salesforce_table_description_header,
)
from bietlejuice.base.sst.domains.salesforce.clean.transform import (
    in_memory_cdc_udpate,
)
from bietlejuice.base.sst.domains.salesforce.recovery.volume import (
    save_dlq_volume_metrics,
)

logger = QuintoAndarLogger("sst.pipelines.salesforce.dlq")

RAW_SCHEMA = "datalake_salesforce_raw"
CLEAN_SCHEMA = "datalake_salesforce_clean"
RECOVERY_EVENT_TYPE = "RECOVERY"
RECOVERY_SOURCE_FILE = "RECOVERY"
LAST_MODIFIED_DATE_COL = "LastModifiedDate"
UNIQUE_GRAIN = [
    "id_record",
    "transaction_key",
    "sequence_number",
    "commit_number",
]
RAW_DROP_COLS = {"source_file", "ts_load", "ChangeEventHeader"}


@default_args(
    optional_args=[
        dict(
            name="dag_name",
            flags=["--dag_name", "--dag-name"],
            type=str,
            required=False,
            default="",
            help="DAG name (optional).",
        ),
        dict(
            name="partition_date",
            flags=["--partition_date", "--partition-date"],
            type=str,
            required=True,
            help="Partition date (YYYY-MM-DD).",
        ),
        dict(
            name="partition_hour",
            flags=["--partition_hour", "--partition-hour"],
            type=str,
            required=True,
            help="Partition hour (HH).",
        ),
        dict(
            name="api_entity",
            flags=["--api_entity", "--api-entity"],
            type=str,
            required=True,
            help="Salesforce SObject API name (e.g. Case).",
        ),
        dict(
            name="salesforce_endpoint",
            flags=["--salesforce_endpoint", "--salesforce-endpoint"],
            type=str,
            required=True,
            help="Salesforce API base endpoint URL.",
        ),
        dict(
            name="bucket",
            flags=["--bucket"],
            type=str,
            required=True,
            help="Datalake bucket used to persist DLQ volume metrics.",
        ),
    ]
)
@logger(exclude_return=True)
def dlq_pipeline(cfg):
    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger.info(f"m=events_dlq, msg=Starting DLQ for {job_name=} {cfg=}")
    spark = retrieve_spark_session(job_name=job_name)

    raw_target_table = f"{RAW_SCHEMA}.{cfg.target_table}"
    base_endpoint = cfg.salesforce_endpoint.rstrip("/")
    access_token = retrieve_token(endpoint=base_endpoint, env=cfg.env)
    headers = build_salesforce_table_description_header(access_token)
    subject_url = f"{base_endpoint}{SUBJECT_ENDPOINT}".format(table=cfg.api_entity)

    schema_definition = get_request(
        endpoint=f"{subject_url}/describe",
        headers=headers,
    )

    updated_lst = retrieve_missing_events(
        spark=spark,
        target_table=cfg.target_table,
        partition_date=cfg.partition_date,
        partition_hour=cfg.partition_hour,
        raw_schema=RAW_SCHEMA,
        clean_schema=CLEAN_SCHEMA,
    )
    logger.info(f"m=events_dlq, msg=Number of events found: {len(updated_lst)}")
    if not updated_lst:
        logger.info("m=events_dlq, msg=No records to be fetched from API")
        _save_dlq_volume(spark, cfg)
        return

    raw_columns = spark.read.table(raw_target_table).columns + ["Id"]
    api_schema = [
        (field["name"], field["type"])
        for field in schema_definition["fields"]
        if field["name"] in raw_columns
    ]
    columns_name = [name for name, _ in api_schema]

    updated_queries, _ = build_query_chunks(
        id_lst=updated_lst,
        columns_name=columns_name,
        api_entity=cfg.api_entity,
    )
    if not updated_queries:
        logger.info("m=events_dlq, msg=No recovery queries to send to API")
        _save_dlq_volume(spark, cfg)
        return

    dlq_df = retrieve_salesforce_event(
        spark=spark,
        api_entity=cfg.api_entity,
        queries=updated_queries,
        event_type=RECOVERY_EVENT_TYPE,
        api_schema=api_schema,
        base_endpoint=base_endpoint,
        access_token=access_token,
        last_modified_date_col=LAST_MODIFIED_DATE_COL,
        recovery_source_file=RECOVERY_SOURCE_FILE,
    )

    ts_load = standard_now()
    remapped_df = (
        apply_schema_remaps(
            spark=spark,
            df=dlq_df,
            target_table=raw_target_table,
            skip_new_columns=True,
            api_to_cdc_struct=True,
        )
        .withColumn("ts_load", F.lit(ts_load))
        .withColumn("partition_date", F.lit(cfg.partition_date))
        .withColumn("partition_hour", F.lit(cfg.partition_hour))
        .dropDuplicates(subset=UNIQUE_GRAIN)
    )

    validate_and_upsert(
        spark=spark,
        target_table=raw_target_table,
        source_df=remapped_df,
        match_fields=UNIQUE_GRAIN,
    )
    reprocessed_df = reprocess_cdc_events(
        spark=spark,
        table=cfg.target_table,
        id_list=updated_lst,
    )
    _save_dlq_volume(spark, cfg, raw_df=remapped_df, clean_df=reprocessed_df)
    logger.info("m=events_dlq, msg=Pipeline completed")


def _save_dlq_volume(spark, cfg, raw_df=None, clean_df=None):
    """Unpack ``cfg`` for the domain-level metric writer."""
    save_dlq_volume_metrics(
        spark=spark,
        bucket=cfg.bucket,
        target_table=cfg.target_table,
        env=cfg.env,
        partition_date=cfg.partition_date,
        partition_hour=cfg.partition_hour,
        raw_df=raw_df,
        clean_df=clean_df,
    )


def reprocess_cdc_events(spark, table, id_list):
    """Replay full raw CDC history for ``id_list`` into the clean table."""
    if not id_list:
        logger.info("m=reprocess_cdc_events, msg=No IDs to reprocess")
        return

    raw_table = f"{RAW_SCHEMA}.{table}"
    clean_table = f"{CLEAN_SCHEMA}.{table}"
    ids_df = spark.createDataFrame(
        [(record_id,) for record_id in id_list], ["id_record"]
    )
    event_df = spark.read.table(raw_table).join(
        F.broadcast(ids_df), "id_record", "inner"
    )

    cols = [col for col in event_df.columns if col not in RAW_DROP_COLS]
    event_df = event_df.select(cols).withColumn(
        "committed_at",
        F.date_format(F.to_timestamp(F.col("commit_ts") / 1000), "yyyy-MM-dd HH:mm:ss"),
    )

    has_create = (
        event_df.select("id_record")
        .where(F.col("event_type").isin("CREATE", "RECOVERY"))
        .distinct()
    )
    unique_events = has_create.join(event_df, ["id_record"], "inner")
    update_df = (
        in_memory_cdc_udpate(normalize_df_columns(unique_events))
        .dropDuplicates(UNIQUE_GRAIN)
        .withColumn("ts_load", F.lit(standard_now()))
    )

    validate_and_upsert(
        spark=spark,
        target_table=clean_table,
        source_df=update_df,
        match_fields=UNIQUE_GRAIN,
    )
    return update_df


if __name__ == "__main__":
    dlq_pipeline()
