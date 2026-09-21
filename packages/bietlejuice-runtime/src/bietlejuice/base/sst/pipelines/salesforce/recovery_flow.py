from datetime import datetime

import pyspark.sql.functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.configs.salesforce import SUBJECT_ENDPOINT
from bietlejuice.base.sst.core.api.request import get_request
from bietlejuice.base.sst.core.utils.common import validate_and_upsert
from bietlejuice.base.sst.core.utils.time import build_hour_window
from bietlejuice.base.sst.core.utils.transforms import apply_schema_remaps
from bietlejuice.base.sst.domains.salesforce.api.calls import (
    build_query_chunks,
    get_deleted_ids,
    get_updated_ids,
    get_updated_lst_system_mod,
    retrieve_salesforce_event,
)
from bietlejuice.base.sst.domains.salesforce.api.credentials import retrieve_token
from bietlejuice.base.sst.domains.salesforce.api.headers import (
    build_salesforce_table_description_header,
)

logger = QuintoAndarLogger("sst.pipelines.salesforce.recovery_flow")


DEFAULT_PARALLELISM = 8
DEFAULT_CHUNK_SIZE = 200
RECOVERY_EVENT_TYPE = "RECOVERY"
RECOVERY_SOURCE_FILE = "RECOVERY"
LAST_MODIFIED_DATE_COL = "LastModifiedDate"


def collect_raw_table_columns(spark, target_schema, target_table):
    """Return ``(column_names, schema)`` for an existing raw Delta table."""
    full_table = f"{target_schema}.{target_table}"
    table_schema = spark.read.table(full_table).schema
    return [field.name for field in table_schema], table_schema


@logger(exclude_return=True)
def events_case_recovery(
    spark,
    api_entity: str,
    salesforce_endpoint: str,
    dag_name: str,
    job_name: str,
    target_schema: str,
    target_table: str,
    env: str,
    partition_date: str,
    partition_hour: str,
):

    full_job_name = f"{dag_name}.{job_name}"
    full_target_table = f"{target_schema}.{target_table}"

    logger.info(
        f"m=events_case_recovery, msg=Starting recovery for {full_job_name=} "
        f"{api_entity=} {full_target_table=} {salesforce_endpoint=}"
    )

    # retrieve_token already rejects a falsy endpoint, but rstrip runs first and
    # would surface as an opaque AttributeError on NoneType. A DAG that never
    # passes --salesforce_endpoint only fails here, when AppFlow misses an hour.
    if not salesforce_endpoint:
        raise ValueError(
            f"salesforce_endpoint is required to run recovery for {full_target_table}; "
            f"set it in the DAG conf and forward it to the cdc_raw task"
        )

    base_endpoint = salesforce_endpoint.rstrip("/")
    access_token = retrieve_token(endpoint=base_endpoint, env=env)
    headers = build_salesforce_table_description_header(access_token)
    subject_url = f"{base_endpoint}{SUBJECT_ENDPOINT}".format(table=api_entity)

    # full_hour = False -> We cover only up to HH:59:59
    start_ts, end_ts = build_hour_window(
        partition_date, partition_hour, full_hour=False
    )

    logger.info(f"m=events_case_recovery, msg=Window {start_ts=} {end_ts=}")

    schema_definition = get_request(
        endpoint=f"{subject_url}/describe",
        headers=headers,
    )

    is_replicateable = schema_definition.get("replicateable", True)
    logger.info(f"m=events_case_recovery, msg={is_replicateable=}")

    updated_lst = []
    deleted_lst = []

    if is_replicateable:
        logger.info("m=events_case_recovery, msg=Calling updated and deleted endpoints")

        updated_lst = get_updated_ids(
            subject_url=subject_url,
            access_token=access_token,
            start_ts=start_ts,
            end_ts=end_ts,
        )
        logger.info(f"m=events_case_recovery, msg={len(updated_lst)} updated IDs found")

        deleted_lst = get_deleted_ids(
            subject_url=subject_url,
            access_token=access_token,
            start_ts=start_ts,
            end_ts=end_ts,
        )
        logger.info(f"m=events_case_recovery, msg={len(deleted_lst)} deleted IDs found")

    else:
        logger.info("m=events_case_recovery, msg=Calling SystemMod API endpoint")

        updated_lst = get_updated_lst_system_mod(
            endpoint=subject_url,
            partition_date=partition_date,
            api_entity=api_entity,
            access_token=access_token,
            partition_hour=partition_hour,
        )

    if not updated_lst and not deleted_lst:
        logger.info("m=events_case_recovery, msg=No records to be fetched from API")
        return

    raw_columns = spark.read.table(full_target_table).columns + ["Id"]
    api_schema = [
        (field["name"], field["type"])
        for field in schema_definition["fields"]
        if field["name"] in raw_columns
    ]
    columns_name = [name for name, _ in api_schema]

    updated_queries = []
    deleted_queries = []

    if updated_lst:
        updated_queries, _ = build_query_chunks(
            id_lst=updated_lst,
            columns_name=columns_name,
            api_entity=api_entity,
        )

    if deleted_lst:
        logger.info(
            f"m=events_case_recovery, "
            f"msg={len(deleted_lst)} deleted rows to be sent to API"
        )

        deleted_queries, _ = build_query_chunks(
            id_lst=deleted_lst,
            columns_name=columns_name,
            api_entity=api_entity,
        )

    logger.info(
        f"m=events_case_recovery, "
        f"msg={len(updated_queries)} recovery queries to be sent to API"
    )
    logger.info(
        f"m=events_case_recovery, "
        f"msg=Parallelizing dataframe with {DEFAULT_PARALLELISM} partitions"
    )

    recovered_df = None
    deleted_df = None

    if updated_queries:
        recovered_df = retrieve_salesforce_event(
            spark=spark,
            api_entity=api_entity,
            queries=updated_queries,
            event_type=RECOVERY_EVENT_TYPE,
            api_schema=api_schema,
            base_endpoint=base_endpoint,
            access_token=access_token,
            last_modified_date_col=LAST_MODIFIED_DATE_COL,
            recovery_source_file=RECOVERY_SOURCE_FILE,
        )

    if deleted_queries:
        deleted_df = retrieve_salesforce_event(
            spark=spark,
            api_entity=api_entity,
            queries=deleted_queries,
            event_type="DELETE",
            api_schema=api_schema,
            base_endpoint=base_endpoint,
            access_token=access_token,
            last_modified_date_col=LAST_MODIFIED_DATE_COL,
            recovery_source_file=RECOVERY_SOURCE_FILE,
        )

    if recovered_df is not None and deleted_df is not None:
        events_df = recovered_df.unionByName(deleted_df)
    elif recovered_df is not None:
        events_df = recovered_df
    else:
        events_df = deleted_df

    ts_load = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    remapped_df = (
        apply_schema_remaps(
            spark=spark,
            df=events_df,
            target_table=full_target_table,
            skip_new_columns=True,
            api_to_cdc_struct=True,
        )
        .withColumn("ts_load", F.lit(ts_load))
        .withColumn("partition_date", F.lit(partition_date))
        .withColumn("partition_hour", F.lit(partition_hour))
    )

    unique_grain = [
        "id_record",
        "transaction_key",
        "sequence_number",
        "commit_number",
    ]

    remapped_df = remapped_df.dropDuplicates(subset=unique_grain)

    validate_and_upsert(
        spark=spark,
        target_table=full_target_table,
        source_df=remapped_df,
        match_fields=unique_grain,
        skip_matched=True,
    )
