from argparse import ArgumentParser
from datetime import datetime
from pyspark.sql import DataFrame
from pyspark.sql.utils import AnalysisException
from pyspark.sql.functions import lit

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark.spark_table_storage_format import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.loaders.spark_metastore_loader import SparkMetastoreLoader
from bietlejuice.services.metastore_services import SparkMetastoreService


def get_ddl_schema_from_amplitude_raw(
        metastore_service: SparkMetastoreService,
        raw_database_name: str,
        raw_table_name: str
    ) -> str:
    """
    Returns the schema of the raw table in DDL format, i.e., a string with the columns and their data types.
    For example:
    ```
    amplitude_attribution_ids array<string>,
    amplitude_id bigint,
    city string,
    client_event_time string,
    client_upload_time string,
    country string,
    data string,
    data_type string,
    device_carrier string,
    device_family string
    ```

    This is useful because if we inform the schema when reading the JSON, Spark is a lot faster. This is very
    important for Amplitude, because it has a lot of partitions, which makes inferring the schema expensive. So we
    just use what's informed in the Metastore.
    """

    table_schema = metastore_service.get_table_schema(raw_database_name, raw_table_name)
    return ",\n".join([
        f"{column_name} {data_type}" for column_name, data_type in table_schema.items()
    ])

def read_raw_df(base_path: str, execution_date: datetime, raw_ddl: str) -> DataFrame:
    """
    Reads amplitude raw events table by going straight to the correct partition.
    That saves a lot of time parsing irrelevant partitions. That is significant, since this table
    has so many of them.
    """

    try:
        return spark.read.schema(raw_ddl).json(
            f"{base_path}/year={execution_date.year}/month={execution_date.month}/day={execution_date.day}"
        ).withColumn("year", lit(execution_date.year))\
        .withColumn("month", lit(execution_date.month))\
        .withColumn("day", lit(execution_date.day))
    
    except AnalysisException as error:
        if error.getErrorClass() != "PATH_NOT_FOUND":
            raise error
        logger.info(f"msg=fail to get events from {execution_date}, cause={error}")

JOB_NAME = "load_incremental_clean"

logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(JOB_NAME)
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("table_name")
parser.add_argument("--partition_by", nargs="+", dest="partition_by", required=False)

if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    partition_cols = args.partition_by

    logger.info(
        f"m=__main__, date={execution_date}, source={source}, "
        f"table_name={table_name}, msg=Job started"
    )

    execution_date = datetime.strptime(execution_date, "%Y-%m-%d")
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    delta_loader = DeltaLoader()

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    db_clean_name = db_info["db_clean_databricks"]
    db_clean_path = db_info["db_clean_path"]
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=source, table_name=table_name, layer="clean"
    )

    raw_ddl = get_ddl_schema_from_amplitude_raw(
        metastore_service=spark_metastore_service,
        raw_database_name=db_info["db_raw_databricks"],
        raw_table_name=table_name,
    )
    raw_df = read_raw_df(
        base_path=f'{db_info["db_raw_path"]}/{table_name}',
        execution_date=execution_date,
        raw_ddl=raw_ddl,
    )
    df = spark.sql(query, df=raw_df)

    df_cols = df.columns

    if('id_app' in df_cols):
        df = df.withColumn("id_app",df.id_app.cast('bigint'))
    if('id_schema' in df_cols):
        df = df.withColumn("id_schema",df.id_schema.cast('bigint'))
    if('location_lat' in df_cols):
        df = df.withColumn("location_lat",df.location_lat.cast('string'))
    if('location_lng' in df_cols):
        df = df.withColumn("location_lng",df.location_lng.cast('string'))

    df = df.select(df_cols)

    delta_loader.load_table(
        table_name=f"{db_clean_name}.{table_name}",
        path=f"{db_clean_path}{table_name}",
        source_df=df,
        partition_by=partition_cols,
    )
