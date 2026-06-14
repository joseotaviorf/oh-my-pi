import json

import pyspark.sql.functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.utils.common import default_args

logger = QuintoAndarLogger("sst.pipelines.quality.contracts.scd_type2")


def validate_scd_type2(cfg):
    fail_lst = []
    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger.info(
        f"m=validate_scd_type2, msg=Starting SCD Type 2 validation, {job_name=}"
    )
    logger.info(f"m=validate_scd_type2, msg=Config received, {cfg=}")

    df = spark.read.table(f"{cfg.target_schema}.{cfg.target_table}")
    unique_grain = json.loads(cfg.unique_grain)
    is_current_column = cfg.is_current_column
    logger.info(
        f"m=validate_scd_type2, msg=Checking if the unique grain is unique, {unique_grain=}"
    )
    is_unique = (
        df.where(F.col(is_current_column))
        .groupby(*unique_grain)
        .agg(F.count("*").alias("total"))
        .filter(F.col("total") > 1)
    )
    unique_count = is_unique.count()
    logger.info(
        f"m=validate_scd_type2, msg=Number of rows with duplicate unique grain, {unique_count=}"
    )
    if unique_count:
        fail_lst.append(
            f"SCD Type 2 validation failed, duplicate unique grain found, {is_unique.count()=}"
        )

    unique_ids = df.select(*unique_grain).distinct()
    active_ids = (
        df.where(F.col(is_current_column))
        .select(*unique_grain)
        .withColumn("is_active", F.lit(True))
    )

    has_missing_value = (
        unique_ids.join(active_ids, on=unique_grain, how="left")
        .fillna(False, subset=["is_active"])
        .where(~F.col("is_active"))
    )

    missing_count = has_missing_value.count()
    logger.info(
        f"m=validate_scd_type2, msg=Number of rows with missing value in unique grain, {missing_count=}"
    )
    if missing_count:
        fail_lst.append(
            f"SCD Type 2 validation failed, missing value in unique grain found, {has_missing_value.count()=}"
        )

    for fail in fail_lst:
        logger.error(f"m=validate_scd_type2, msg=SCD Type 2 validation failed, {fail=}")
    if len(fail_lst) > 0:
        raise ValueError(
            f"m=validate_scd_type2, msg=SCD Type 2 validation failed, {fail_lst=}"
        )
    logger.info("m=validate_scd_type2, msg=SCD Type 2 validation passed")
    return True


@logger(exclude_return=True)
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
            name="unique_grain",
            flags=["--unique_grain", "--grain"],
            type=str,
            required=True,
            help="Serialized json string of List[str] of columns that form the unique grain of type 2 columns. Meaning, one active (_is_current=True) row per unique grain.",
        ),
        dict(
            name="is_current_column",
            flags=["--is_current_column", "--is-current-column"],
            type=str,
            required=False,
            default="_is_current",
            help="Name of the boolean column that flags the current row. Defaults to '_is_current'.",
        ),
    ]
)
def run(cfg):
    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger = QuintoAndarLogger(job_name)
    logger.info(f"m=run, msg=Starting SCD Type 2 validation, {job_name=}")
    logger.info(f"m=run, msg=Config received, {cfg=}")
    validate_scd_type2(cfg)
    logger.info("m=run, msg=SCD Type 2 validation completed")
    return True


if __name__ == "__main__":
    run()
