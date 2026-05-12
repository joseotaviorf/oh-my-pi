from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.observability.sensors import partition_has_data
from bietlejuice.base.sst.core.utils.common import (
    validate_and_write,
)
from bietlejuice.base.sst.domains.sfmc.raw.api import (
    fetch_object_rows,
    get_access_token,
    resolve_api_credentials,
)
from bietlejuice.base.sst.domains.sfmc.raw.schema import (
    align_and_cast_with_schema,
    build_schema_columns,
    get_data_extension_schema,
)
from bietlejuice.base.sst.domains.sfmc.raw.transform import normalize_row

logger = QuintoAndarLogger("sst.pipelines.sfmc_raw")


@logger(exclude=["spark"], exclude_return=True)
def sfmc_raw_pipeline(spark, cfg):
    target_table = f"{cfg.target_schema}.{cfg.target_table}"

    if partition_has_data(spark, target_table, cfg.partition_date):
        logger.info(
            "m=sfmc_raw_pipeline, "
            f"msg=Partition already exists for table={target_table}, partition_date={cfg.partition_date}. Skipping."
        )
        return

    credentials = resolve_api_credentials(require_rest_url=True, require_soap_url=True)
    access_token = get_access_token(
        auth_url=credentials["auth_url"],
        client_id=credentials["client_id"],
        client_secret=credentials["client_secret"],
    )
    rows = fetch_object_rows(
        rest_url=credentials["rest_url"],
        access_token=access_token,
        external_key=cfg.external_key,
    )

    if not rows:
        logger.warning(
            "m=sfmc_raw_pipeline, "
            f"msg=No rows returned for external_key={cfg.external_key}, partition_date={cfg.partition_date}"
        )
        return

    schema_fields = get_data_extension_schema(
        soap_url=credentials["soap_url"],
        access_token=access_token,
        customer_key=cfg.external_key,
    )
    schema_columns = build_schema_columns(schema_fields)

    normalized_rows = [normalize_row(row) for row in rows]
    raw_df = spark.createDataFrame(normalized_rows)
    raw_df = align_and_cast_with_schema(raw_df, schema_columns)

    raw_final = (
        raw_df.withColumn("external_key", F.lit(cfg.external_key))
        .withColumn(
            "ts_load",
            F.date_format(F.current_timestamp(), "yyyy-MM-dd HH:mm:ss"),
        )
        .withColumn("partition_date", F.lit(cfg.partition_date))
    )

    partition_filter = f"partition_date = '{cfg.partition_date}'"
    table_location = f"s3a://{cfg.bucket}/raw/{cfg.target_schema}/{cfg.target_table}"
    validate_and_write(
        spark=spark,
        df=raw_final,
        target_table=target_table,
        partition_filter=partition_filter,
        partition_cols=["partition_date"],
        overwrite_schema=True,
        table_location=table_location,
    )

    logger.info("m=sfmc_raw_pipeline, msg=Pipeline completed")
