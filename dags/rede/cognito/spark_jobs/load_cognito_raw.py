from bietlejuice.base.db.datalake_metastore_service import DatalakeMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark.spark_dataframe_service import SparkDataFrameService
from bietlejuice.base.spark.spark_table_storage_format import SparkTableStorageFormat
from bietlejuice.pipeline.incremental_table_loader_pipeline import IncrementalTableLoaderPipeline
from bietlejuice.services.metastore_services.spark_metastore_service import SparkMetastoreService
import boto3
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    TimestampType,
    BooleanType,
    MapType,
    ArrayType,
)
from pyspark.sql import DataFrame
from pyspark.sql.functions import greatest, col, lit, row_number
from pyspark.sql.window import Window
import logging
from argparse import ArgumentParser, Namespace
from datetime import datetime, timezone

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.clients.db_clients import SparkClient

JOB_NAME = "load_cognito_raw"
USER_SCHEMA = StructType([
        StructField("Username", StringType(), True),
        StructField("Attributes", ArrayType(MapType(StringType(), StringType())), True),
        StructField("UserCreateDate", TimestampType(), True),
        StructField("UserLastModifiedDate", TimestampType(), True),
        StructField("Enabled", BooleanType(), True),
        StructField("UserStatus", StringType(), True),
    ]
)
PARTITION_COLS = ["year", "month", "day"]

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_args() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("execution_date", type=str, help="DAG execution date")
    parser.add_argument("user_pool_id", type=str, help="ID of the Cognito user pool")
    args = parser.parse_args()

    logger.info(
        f"""
        m=__main__, env={args.env}, datalake_bucket={args.datalake_bucket},
        source={args.source}, table_name={args.table_name},
        execution_date={args.execution_date}, user_pool_id={args.user_pool_id},
        msg=Starting Spark job...
        """
    )

    return args

def get_all_users(user_pool_id: str) -> list:
    """Returns a list of all users in a given Cognito user pool."""

    region = user_pool_id.split('_')[0]
    cognito = boto3.client('cognito-idp', region_name=region)

    users = []
    pagination_token = None
    kwargs = {
        'UserPoolId': user_pool_id
    }

    users_remain = True
    total = 0
    while users_remain:
        if pagination_token:
            kwargs['PaginationToken'] = pagination_token
        response = cognito.list_users(**kwargs)
        users.extend(response['Users'])
        pagination_token = response.get('PaginationToken', None)
        users_remain = pagination_token is not None
        total += 60
        
        if total % 6000 == 0:
            logger.info(f"m=get_all_users, total={total}, msg=Retrieved {total} users from Cognito user pool {user_pool_id} so far...")

    logger.info(f"m=get_all_users, total={total}, msg=Retrieved {total} users from Cognito user pool {user_pool_id}.")

    return users

def add_year_month_day(users_df: DataFrame) -> DataFrame:
    """Adds year, month and day to dataframe."""
    return (
        SparkDataFrameService()
        .input(users_df)
        .create_year_month_day_columns_from_dataframe_column('UserLastModifiedDate')
        .output()
    )

def transform_into_dataframe(users: list) -> DataFrame:
    """Transforms the users list into a Spark DataFrame, with year, month and day columns"""
    return add_year_month_day(
        SparkClient().create_dataframe(users, USER_SCHEMA).withColumn('Deleted', lit(False))
    )

def filter_dataframe_by_execution_date(df: DataFrame, execution_date: datetime):
    """Since there is no way to run a server-side filter by update date in Cognito, this function does that client-side."""

    return df.where(
        f"""year > {execution_date.year}
        OR (year = {execution_date.year} AND month > {execution_date.month})
        OR (year = {execution_date.year} AND month = {execution_date.month} AND day >= {execution_date.day})"""
    )

def get_deleted_users(users_df: DataFrame, table_name: str, execution_date: datetime) -> DataFrame:
    """
    Gets the most recent row of all non-deleted users, and compares them to the return of the API.
    If they were not returned, they are marked as deleted.
    """

    raw_table = spark.table(f'datalake_cognito_raw.{table_name}').where(
        f"""year < {execution_date.year}
        OR (year = {execution_date.year} AND month < {execution_date.month})
        OR (year = {execution_date.year} AND month = {execution_date.month} AND day < {execution_date.day})"""
    ) # To avoid writing over a partition that is being read, if the DAG is being reexecuted
                     
    window_spec = Window.partitionBy("Username").orderBy(raw_table.UserLastModifiedDate.desc())
    deduped_raw_table = raw_table.withColumn('rw', row_number().over(window_spec))\
                                 .filter(col('rw') == 1)\
                                 .drop('rw')\
                                 .filter(col('Deleted') == False) # Getting most recent row of non-deleted users

    return add_year_month_day(deduped_raw_table.alias('rt').join(
        users_df,
        on=deduped_raw_table.Username == users_df.Username,
        how='left'
    ).filter(users_df.Username.isNull()).selectExpr('rt.*')\
     .withColumn('Deleted', lit(True))\
     .withColumn('Enabled', lit(False))\
     .withColumn('UserLastModifiedDate', lit(execution_date)))

def load_dataframe_into_datalake(users_df: DataFrame, args: Namespace) -> None:
    """Loads a Spark dataframe into a given table in the data lake."""

    db_info = DatalakeMetastoreService.get_db_info(args.env, args.source, args.datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(SparkClient())

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    IncrementalTableLoaderPipeline(
        database_name,
        args.table_name,
        database_location,
        LayerEnum.RAW,
        None,
        PARTITION_COLS,
    ).load_and_register(users_df, format_options)

def main():
    args = parse_args()
    total_users = get_all_users(args.user_pool_id)
    total_users_df = transform_into_dataframe(total_users)

    execution_date = datetime.strptime(args.execution_date, '%Y-%m-%d')
    deleted_users_df = get_deleted_users(total_users_df, args.table_name, execution_date)
    last_modified_users_df = filter_dataframe_by_execution_date(total_users_df, execution_date)
    modified_plus_deleted_df = deleted_users_df.unionByName(last_modified_users_df)

    load_dataframe_into_datalake(modified_plus_deleted_df, args)

if __name__ == '__main__':
    main()