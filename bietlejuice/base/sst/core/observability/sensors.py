# Common sensors for python
# Since bietlejuice doesn't have sensors as we need, we're manually adding it to code here


import boto3
import pyspark.sql.functions as F
from typing import List
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.sst.core.utils.common import _table_exists


logger = QuintoAndarLogger("sst.common.sensors")


@logger(exclude_return=True)
def sensor_for_new_columns(spark, df, table) -> List[str]:
    """
    Return incoming columns that are new to the target table schema.

    Mirrors the "updates" diff used by `_safe_merge_schema`:
    columns present in `df` but absent from the existing target table schema.
    Returns an empty list when the table does not yet exist (first run).
    """
    if not _table_exists(spark, table):
        logger.info(
            f"m=sensor_for_new_columns, msg=Table does not exist yet, skipping diff, table={table}"
        )
        return []

    target_table = spark.read.table(table)
    updates = set(df.columns) - set(target_table.columns)

    logger.info(
        f"m=sensor_for_new_columns, msg=Detected new columns, "
        f"table={table}, new_columns={updates}"
    )
    return updates


@logger(exclude_return=True)
def sensor_table_exists(spark, table_name, fail=True):
    if not _table_exists(spark, table_name):
        logger.error(f"m=sensor_failure, msg= Table {table_name} does not exist")
        if fail:
            raise ValueError(f"Table {table_name} does not exist")
        else:
            return False
    return True


def partition_has_data(spark, table_name, partition_date, partition_hour):
    if not _table_exists(spark, table_name):
        return False

    rows = (
        spark.read.table(table_name)
        .where(F.col("partition_date") == F.lit(partition_date))
        .where(F.col("partition_hour") == F.lit(partition_hour))
        .count()
    )
    return rows > 0


@logger(exclude_return=True)
def sensor_partition_hour(spark, table_name, partition_date, partition_hour, fail=True):
    """
    Follow same pattern as partition_has_date, but for sensors, we should be failing in case of no data and/or no table exists
    """
    # Temporarily skipping Raise in cases where the table doesn't exist
    if not sensor_table_exists(spark, table_name, fail=fail):
        logger.info(f"m=sensor_partition_hour, msg=Table {table_name} does not exist")
        return False
    rows = partition_has_data(spark, table_name, partition_date, partition_hour)
    if rows:
        logger.info(
            f"m=sensor_success, msg= {rows} rows found at {table_name=}\t{partition_date=}{partition_hour=}"
        )
        return True
    else:
        logger.error(
            f"m=sensor_failure, msg= No rows found at {table_name=}\t{partition_date=}{partition_hour=}"
        )
        if fail:
            raise ValueError(
                f"Sensor failed for {table_name=}\t{partition_date=}{partition_hour=}"
            )
        return False


@logger(exclude_return=True)
def sensor_s3_file_exists(bucket, s3_path, fail=True):
    s3_client = boto3.client("s3")
    file_lst = []

    response = s3_client.list_objects_v2(Bucket=bucket, Prefix=s3_path)
    if "Contents" in response:
        files = response["Contents"]
        for file in files:
            if "Key" in file:
                file_lst.append(file["Key"])
    if len(file_lst) > 0:
        logger.info(
            f"m=sensor_success, msg=s3_file_exists, s3_path={s3_path}, file_lst={file_lst}"
        )
        return True
    else:
        logger.error(
            f"m=sensor_failure, msg=s3_file_not_exists, s3_path={s3_path}, file_lst={file_lst}"
        )
        if fail:
            raise ValueError(f"s3_file not available: {s3_path} at bucket: {bucket}")
        return False
