# Common sensors for python
# Since bietlejuice doesn't have sensors as we need, we're manually adding it to code here


import boto3
import pyspark.sql.functions as F
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.sst.core.utils.common import _table_exists


logger = QuintoAndarLogger("sst.common.sensors")


@logger(exclude_return=True)
def sensor_table_exists(spark, table_name, fail=True):
    if not _table_exists(spark, table_name) and fail:
        logger.error(f"m=sensor_failure, msg= Table {table_name} does not exist")
        raise ValueError(f"Table {table_name} does not exist")
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
    # If table doesn't exists, we should fail the job"
    sensor_table_exists(spark, table_name)
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
