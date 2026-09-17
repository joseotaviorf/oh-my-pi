from datetime import datetime

import pyspark.sql.functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.configs.salesforce import SUBJECT_ENDPOINT
from bietlejuice.base.sst.core.api.request import get_request
from bietlejuice.base.sst.core.utils.common import (
    build_partition_filter,
    default_args,
    retrieve_spark_session,
    validate_and_write,
)
from bietlejuice.base.sst.domains.salesforce.api.calls import (
    build_fetch_partition_closure,
    build_query_chunks,
    get_updated_deleted_lst,
    get_updated_lst_system_mod,
    paralelize_queries,
)
from bietlejuice.base.sst.domains.salesforce.api.credentials import retrieve_token
from bietlejuice.base.sst.domains.salesforce.api.headers import (
    build_salesforce_table_description_header,
)
from bietlejuice.base.sst.domains.salesforce.api.logs import conform_and_save_api_logs
from bietlejuice.base.sst.domains.salesforce.api.schemas import (
    API_RESPONSE_SCHEMA,
    SF_RAW_SCHEMA_COLS,
)
from bietlejuice.base.sst.domains.salesforce.common.types import (
    build_salesforce_type_schema,
)

logger = QuintoAndarLogger("sst.pipelines.salesforce.api_v2")

PARALELISM = 10


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
            name="bucket",
            flags=["--bucket"],
            type=str,
            required=True,
            help="S3 Bucket Name.",
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
            required=False,
            default=None,
            help="Partition hour (HH). Optional; when omitted the job runs at "
            "daily granularity.",
        ),
        dict(
            name="api_entity",
            flags=["--api_entity"],  # "--api-entity"],
            type=str,
            required=True,
            help="Salesforce API Entity name (OBJECT Name). E.g: Case,Task",
        ),
        dict(
            name="endpoint",
            flags=["--endpoint"],
            type=str,
            required=True,
            help="Api BASE endpoint, usually associated with environment",
        ),
    ]
)
def pipeline_api_raw(cfg):

    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger.info(f"m=pipeline_api_raw, cfg: {cfg}")
    logger.info(
        f"m=pipeline_api_raw, msg=Starting API_V2 for {job_name=}\t {cfg.api_entity}"
    )
    spark = retrieve_spark_session(job_name=job_name)

    logger.info("m=pipeline_api_raw, msg=Retrieving Token and Headers")
    access_token = retrieve_token(endpoint=cfg.endpoint, env=cfg.env)

    subject_base_url = f"{cfg.endpoint}{SUBJECT_ENDPOINT}".format(table=cfg.api_entity)
    header = build_salesforce_table_description_header(access_token)
    logger.info("m=pipeline_api_raw, msg=Retrieving Schema definition")

    schema_definition = get_request(
        endpoint=subject_base_url + "/describe", headers=header
    )
    # If this is False, we can't use the default /updated /deleted endpoints, we should use SystemMod
    is_replicateable = schema_definition.get("replicateable", True)
    logger.info(f"m=pipeline_api_raw, msg={is_replicateable=}")

    updated_lst = []
    if is_replicateable:
        logger.info("m=pipeline_api_raw, msg=Calling updated/deleted endpoint")
        updated_lst = get_updated_deleted_lst(
            endpoint=subject_base_url,
            partition_date=cfg.partition_date,
            access_token=access_token,
            days=1,
            partition_hour=cfg.partition_hour,
        )
    else:
        logger.info("m=pipeline_api_raw, msg=Calling SystemMod API endpoint")
        updated_lst = get_updated_lst_system_mod(
            endpoint=cfg.endpoint,
            partition_date=cfg.partition_date,
            api_entity=cfg.api_entity,
            access_token=access_token,
            days=1,
            partition_hour=cfg.partition_hour,
        )

    if len(updated_lst) == 0:
        logger.info("m=pipeline_api_raw, msg=No records to be fetched from API")
        return

    table_columns = SF_RAW_SCHEMA_COLS[cfg.api_entity.lower()]
    api_schema = [
        (field["name"], field["type"])
        for field in schema_definition["fields"]
        if field["name"] in table_columns
    ]
    columns_name = [name for name, _ in api_schema]

    logger.info(f"m=pipeline_api_raw, msg=Mapping schema columns: {api_schema}")
    queries, _ = build_query_chunks(
        id_lst=updated_lst, columns_name=columns_name, api_entity=cfg.api_entity
    )
    logger.info(f"m=pipeline_api_raw, msg={len(queries)} queries to be sended to API")
    logger.info(
        f"m=pipeline_api_raw, msg=Parallelizing dataframe with {PARALELISM} partitions"
    )

    request_df = paralelize_queries(spark=spark, queries=queries, paralelism=PARALELISM)
    fetch_partition = build_fetch_partition_closure(cfg.endpoint, access_token)
    spark_schema = build_salesforce_type_schema(api_schema)
    logger.info("m=pipeline_api_raw, msg=Fetching data from API")
    # Keep it for logs
    api_result_df = (
        request_df.select("idx", "query")
        .repartition(PARALELISM)
        .mapInPandas(fetch_partition, schema=API_RESPONSE_SCHEMA)
        .withColumn("record", F.from_json(F.col("record_json"), spark_schema))
        # Persist after API calls, if we're getting a lot of values, use persist() with disk + memory level
        .cache()
    )

    api_errors_count = api_result_df.where(F.col("error").isNotNull()).count()
    if api_errors_count > 0:
        logger.warning(
            f"m=pipeline_api_raw, msg={api_errors_count} errors found at API"
        )
    else:
        logger.info("m=pipeline_api_raw, msg=No API request errors found")

    # Log api calls
    logger.info("m=pipeline_api_raw, msg=Saving API response to logs")
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    result_df = (
        # Error rows carry no record_json, so select("record.*") would turn
        # each of them into an all-NULL record (null id_record/system_modstamp)
        # in the raw table, which the clean layer's quality checks then reject.
        # Errors belong in salesforce_api_logs (written below), not in raw.
        api_result_df.where(F.col("error").isNull() & F.col("record_json").isNotNull())
        .select("record.*")
        .withColumnRenamed("Id", "id_record")
        .withColumn("entity_type", F.lit(cfg.api_entity))
        .withColumn("ts_load", F.lit(now))
        .withColumn("partition_date", F.lit(cfg.partition_date))
    )
    partition_filter_cols = {"partition_date": cfg.partition_date}
    partition_cols = ["partition_date"]
    # "00" is a legitimate hour — compare against None, never truthiness.
    if cfg.partition_hour is not None:
        result_df = result_df.withColumn("partition_hour", F.lit(cfg.partition_hour))
        partition_filter_cols["partition_hour"] = cfg.partition_hour
        partition_cols.append("partition_hour")
    partition_filter = build_partition_filter(partition_filter_cols)
    logger.info(f"m=salesforce_raw_pipeline, msg=Partition columns: {partition_cols}")

    table_location = f"s3a://{cfg.bucket}/raw/salesforce/{cfg.target_table}"
    target_table = f"{cfg.target_schema}.{cfg.target_table}"

    validate_and_write(
        spark=spark,
        df=result_df,
        target_table=target_table,
        partition_filter=partition_filter,
        partition_cols=partition_cols,
        overwrite_schema=True,
        table_location=table_location,
        # sync_hive=False,
        # sync_secondary_catalog=True,
    )

    logger.info("m=salesforce_raw_pipeline, msg=Logging API results")
    conform_and_save_api_logs(
        spark=spark,
        df=api_result_df,
        api_entity=cfg.api_entity,
        target_table=target_table,
        job_name=job_name,
        partition_date=cfg.partition_date,
        bucket=cfg.bucket,
        partition_hour=cfg.partition_hour,
    )

    # Fail AFTER the raw and log writes so the error details are queryable and
    # a retry (idempotent replaceWhere on both tables) can refetch the records
    # that errored. query_all_with_retry already retried per query, so an error
    # surviving to here means those records are missing from this partition —
    # succeeding silently would be data loss.
    if api_errors_count > 0:
        raise RuntimeError(
            f"{api_errors_count} Salesforce API request(s) failed for "
            f"{cfg.api_entity}; the affected records are missing from "
            f"partition_date={cfg.partition_date}. See "
            f"datalake_sst_metrics.salesforce_api_logs (job_name={job_name})."
        )
    logger.info("m=salesforce_raw_pipeline, msg=All Done!")


if __name__ == "__main__":
    pipeline_api_raw()
