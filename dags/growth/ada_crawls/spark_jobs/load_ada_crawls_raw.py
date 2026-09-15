import logging
import re
from argparse import ArgumentParser
from datetime import datetime
from functools import reduce
from typing import Optional

from pyspark.sql import DataFrame
from pyspark.sql.functions import lit
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
)
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.services.metastore_services import MetastoreServiceFactory
from bietlejuice.services.metastore_services.metastore_service import (
    MetastoreService,
)

JOB_NAME = "load_ada_crawls_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
dbutils = BaseDBUtils().get_dbutils()
RAW_PARTITION_COLS = ["date", "device"]


def get_most_recent_crawl(
    crawl_bucket_path: str, load_start_date: str, load_end_date: str
) -> Optional[str]:
    """
    Finds the most recent crawl folder within a specified date range in the given S3 bucket path.

      Args:
        crawl_bucket_path (str): The S3 bucket path where crawl folders are stored.
        load_start_date (str): The start date (inclusive) in 'YYYY-MM-DD' format to filter crawl folders.
        load_end_date (str): The end date (inclusive) in 'YYYY-MM-DD' format to filter crawl folders.

      Returns:
        most_recent_crawl (str): The most recent crawl folder within the date range, or None if not found.
    """
    folder_items = dbutils.fs.ls(crawl_bucket_path)
    date_pattern = r"^\d{4}-\d{2}-\d{2}$"

    load_start_date = datetime.strptime(load_start_date, "%Y-%m-%d")
    load_end_date = datetime.strptime(load_end_date, "%Y-%m-%d")
    most_recent_crawl_date = load_start_date
    most_recent_crawl = None

    for item in folder_items:
        if item.isDir():
            folder_name = item.name.strip("/")
            if re.match(date_pattern, folder_name):
                crawl_date = datetime.strptime(folder_name, "%Y-%m-%d")
                if (
                    load_start_date <= crawl_date <= load_end_date
                    and crawl_date > most_recent_crawl_date
                ):
                    most_recent_crawl_date = crawl_date
                    most_recent_crawl = item
    return most_recent_crawl


def get_internal_all_or_issues_overview_dataframe(
    most_recent_crawl_file_path: str, crawl_device: str, crawl_date: str
) -> DataFrame:
    """
    Reads the internal_all.csv or the issues_overview_report.csv file from the given path and returns a DataFrame with the data.

      Args:
        most_recent_crawl_file_path (str): The path to the CSV file to read.
        crawl_device (str): The device type of the crawl (desktop or mobile).
        crawl_date (str): The date of the crawl in 'YYYY-MM-DD' format.

      Returns:
        df (DataFrame): The DataFrame with the data from the CSV file.
    """
    df = (
        spark.read.option("header", "true")
        .option("multiline", "true")
        .option("escape", '"')
        .option("quote", '"')
        .csv(most_recent_crawl_file_path)
    )
    df = df.withColumn("device", lit(crawl_device)).withColumn("date", lit(crawl_date))

    if df.count() == 0:
        raise FileNotFoundError(
            f"m=get_internal_all_or_issues_overview_dataframe, msg=”{most_recent_crawl_file_path}” file not found."
        )

    return df


def get_issues_dataframe(
    most_recent_crawl_issues_path: str, crawl_device: str, crawl_date: str
) -> DataFrame:
    """
    Reads the issues_reports/ folder from the given path and returns a DataFrame with the all the issues data.

      Args:
        most_recent_crawl_issues_path (str): The path to the issues_reports/ folder to read.
        crawl_device (str): The device type of the crawl (desktop or mobile).
        crawl_date (str): The date of the crawl in 'YYYY-MM-DD' format.

      Returns:
        df (DataFrame): The DataFrame with the data from the CSV files inside the issues_reports/ folder.
    """
    report_file_list = dbutils.fs.ls(most_recent_crawl_issues_path)

    if not report_file_list:
        raise FileNotFoundError(
            f"m=get_issues_dataframe, msg=No files found in path: {most_recent_crawl_issues_path}"
        )

    rows = []
    for report_file in report_file_list:
        if report_file.name.endswith(".csv"):
            df = (
                spark.read.option("header", "true")
                .option("multiline", "true")
                .option("escape", '"')
                .option("quote", '"')
                .csv(report_file.path)
            )
            if "Address" in df.columns or "Source" in df.columns:
                issue_name = (
                    report_file.name.replace(".csv", "").replace("_", " ").title()
                )
                if "Source" in df.columns:
                    df = df.withColumnRenamed("Source", "Address")
                df_sel = (
                    df.select("Address")
                    .withColumn("issue_name", lit(issue_name))
                    .withColumn("device", lit(crawl_device))
                    .withColumn("date", lit(crawl_date))
                )
                rows.append(df_sel)
    if rows:
        return reduce(lambda df1, df2: df1.unionByName(df2), rows)
    else:
        raise RuntimeError(f"""
        m=get_issues_dataframe, msg=No dataframes created. None of the files in '{most_recent_crawl_issues_path}' contain the required 'Address' column.
        """)


def have_different_schemas(dfs: list[DataFrame]) -> bool:
    """
    Checks if the schemas of the DataFrames are different.

      Args:
        dfs (list[DataFrame]): The list of DataFrames to check.

      Returns:
        bool: True if the schemas are different, False otherwise.
    """
    schemas = [str(df.schema) for df in dfs]
    return len(set(schemas)) > 1


def reduce_dataframes(dfs: list[DataFrame]) -> DataFrame:
    """
    Reduces the list of DataFrames to a single DataFrame with the same schema.

      Args:
        dfs (list[DataFrame]): The list of DataFrames to reduce.

      Returns:
        DataFrame: The reduced DataFrame.
    """
    if not have_different_schemas(dfs):
        return reduce(lambda df1, df2: df1.unionByName(df2), dfs)

    max_column_count_df = max(dfs, key=lambda d: len(d.columns))
    ref_cols = max_column_count_df.columns

    all_columns = set(ref_cols)
    for df in dfs:
        all_columns.update(df.columns)

    common_schema_dfs = []
    for df in dfs:
        missing_columns = all_columns - set(df.columns)
        for column in missing_columns:
            df = df.withColumn(column, lit(None))
        extras = [c for c in all_columns if c not in ref_cols]
        new_order = list(ref_cols) + extras
        df = df.select(*[f"`{col}`" for col in new_order])
        common_schema_dfs.append(df)

    return reduce(lambda df1, df2: df1.unionByName(df2), common_schema_dfs)


def has_required_items(path: str) -> bool:
    """
    Checks if the S3 bucket path has the required items.

      Args:
        path (str): The S3 bucket path to check.

      Returns:
        bool: True if the path has the required items, False otherwise.
    """
    try:
        contents = [content.name for content in dbutils.fs.ls(path)]
        return "issues_reports/" in contents and "internal_all.csv" in contents
    except:
        return False


def get_dataframe_for_most_recent_crawl(
    crawl_bucket_path: str,
    load_start_date: str,
    load_end_date: str,
    folder_or_file_name: str,
) -> Optional[DataFrame]:
    """
    Gets the issues, internal_all or issues_overview_report DataFrame for the most recent crawl based on the folder_or_file_name.

      Args:
        crawl_bucket_path (str): The path to the crawl bucket.
        load_start_date (str): The start date of the crawl.
        load_end_date (str): The end date of the crawl.
        folder_or_file_name (str): The name of the folder or file to get the DataFrame for.

      Returns:
        DataFrame or None: The DataFrame for the most recent crawl, or None if no crawl in date range or no device folder.
    """
    most_recent_crawl = get_most_recent_crawl(
        crawl_bucket_path, load_start_date, load_end_date
    )
    if most_recent_crawl is None:
        return None

    device_folders = [
        item
        for item in dbutils.fs.ls(most_recent_crawl.path)
        if item.isDir()
        and not item.name.startswith(".")
        and has_required_items(item.path)
    ]
    if not device_folders:
        return None

    most_recent_crawl_date = most_recent_crawl.name.strip("/")
    dfs = []
    for folder in device_folders:
        device = folder.name.strip("/")
        if folder_or_file_name == "issues_reports/":
            df = get_issues_dataframe(
                folder.path + folder_or_file_name, device, most_recent_crawl_date
            )
        else:
            df = get_internal_all_or_issues_overview_dataframe(
                folder.path + folder_or_file_name, device, most_recent_crawl_date
            )
        dfs.append(df)

    if len(dfs) == 1:
        return dfs[0]

    dfs = reduce_dataframes(dfs)
    return dfs


def update_df_with_missing_columns(
    df: DataFrame,
    database_name: str,
    table_name: str,
    spark_metastore_service: MetastoreService,
    fallback_database_name: str = None,
    fallback_table_name: str = None,
) -> DataFrame:
    """
    Updates the DataFrame with the missing columns compared to the table in the database.

      Args:
        df (DataFrame): The DataFrame being loaded to the Datalake.
        database_name (str): The name of the Datalake.
        table_name (str): The name of the table.
        spark_metastore_service (MetastoreService): The metastore service.
        fallback_database_name (str): Prod database when the write target table does not exist yet.
        fallback_table_name (str): Prod table when the write target table does not exist yet.

      Returns:
        DataFrame: The DataFrame with the missing columns.
    """
    schema_database_name = database_name
    schema_table_name = table_name
    if table_name not in spark_metastore_service.get_table_names(database_name):
        if (
            fallback_database_name
            and fallback_table_name
            and fallback_table_name
            in spark_metastore_service.get_table_names(fallback_database_name)
        ):
            schema_database_name = fallback_database_name
            schema_table_name = fallback_table_name
        else:
            return df

    table_schema = spark_metastore_service.get_table_schema(
        database_name=schema_database_name,
        table_name=schema_table_name,
        ignore_partition_keys=True,
    )
    # Glue (the EMR primary metastore) lower-cases column names while the crawl CSVs
    # carry Title Case headers, so a case-sensitive comparison reports every header as
    # missing. Because spark.sql.caseSensitive is false, withColumn then replaces the
    # populated column with NULL instead of adding a new one.
    df_cols = {column.lower() for column in df.columns}
    missing_cols = [field for field in table_schema if field.lower() not in df_cols]
    for field in missing_cols:
        df = df.withColumn(field, lit(None).cast("string"))
    return df


def load_dataframe_into_datalake(
    datalake_bucket: str,
    df: DataFrame,
    environment: str,
    table_name: str,
    source: str,
    target_database_name: str = None,
    target_table_name: str = None,
) -> None:
    """
    Loads a spark DataFrame into the datalake.

      Args:
        datalake_bucket (str): The datalake bucket.
        df (DataFrame): The DataFrame to load.
        environment (str): The environment.
        table_name (str): The name of the table to load the DataFrame into.
        source (str): The source of the data.

      Returns:
        None
    """
    db_info = DatalakeMetastoreService.get_db_info(
        env=environment,
        source=source,  # dag_name
        bucket=datalake_bucket,
    )

    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=target_database_name,
            target_table=target_table_name,
        )
    )
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    s3_loader = S3Loader()
    spark_metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    )
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    spark_metastore_service.create_database(write_database_name)
    updated_df = update_df_with_missing_columns(
        df,
        write_database_name,
        write_table_name,
        spark_metastore_service,
        fallback_database_name=database_name,
        fallback_table_name=table_name,
    )

    s3_loader.load_df(
        df=updated_df,
        s3_path=f"{write_location}{write_table_name}",
        format_options=format_options,
        partitions=RAW_PARTITION_COLS,
        compression="gzip",
    )

    spark_metastore_loader.update_metastore(
        df=updated_df,
        database_name=write_database_name,
        table_name=write_table_name,
        format_options=format_options,
        database_location=write_location,
        partitions=RAW_PARTITION_COLS,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=updated_df,
        database_name=write_database_name,
        table_name=write_table_name,
        partition_cols=RAW_PARTITION_COLS,
    )

    full_write_table_name = f"{write_database_name}.{write_table_name}"
    table_privileges = TablePrivileges.from_environment_default(full_write_table_name)
    if table_privileges and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        table_privileges.apply()


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("bucket")
    parser.add_argument("dag_name")  # source
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("table_name")
    parser.add_argument("folder_or_file_name")
    parser.add_argument("crawl_bucket_path")

    add_validation_target_args(parser)
    return parser.parse_args()


def main():
    args = parse_arguments()

    environment: str = args.environment
    bucket: str = args.bucket
    dag_name: str = args.dag_name
    load_start_date: str = args.load_start_date
    load_end_date: str = args.load_end_date
    table_name: str = args.table_name
    folder_or_file_name: str = args.folder_or_file_name
    crawl_bucket_path: str = args.crawl_bucket_path

    logger.info(f"""
            m=main, environment={environment}, datalake_bucket={bucket}, dag_name={dag_name}, 
            load_start_date={load_start_date}, load_end_date={load_end_date}, table_name={table_name}, 
            folder_or_file_name={folder_or_file_name}, crawl_bucket_path={crawl_bucket_path}.
            msg=Starting Spark Job...
            """)

    if dbutils is None:
        raise RuntimeError("""
            m=main, msg=Failed to initialize dbutils or find its object.
            """)

    webhook_key = (
        GchatWebhooksEnum.AE_ALERTS_PROD
        if environment == "prod"
        else GchatWebhooksEnum.AE_ALERTS_FORNO
    )
    gchat_webhook = None
    try:
        gchat_webhook = dbutils.secrets.get(scope="quintoandar", key=webhook_key)
    except Exception as e:
        logger.warning(
            f"m=main, msg=Could not get GChat webhook for no-crawl notification; notifications will be skipped. error={e}"
        )

    df = get_dataframe_for_most_recent_crawl(
        crawl_bucket_path, load_start_date, load_end_date, folder_or_file_name
    )
    if df is None:
        message_content = (
            f"ADA Crawls: no crawl data available for this run "
            f"(date range {load_start_date}–{load_end_date}, table {table_name}). "
            f"No data loaded; run succeeded."
        )
        logger.warning(f"m=main, msg={message_content}")
        if gchat_webhook:
            try:
                message = Message(content=message_content, destination=gchat_webhook)
                GChatService.send_message(message)
            except Exception as e:
                logger.warning(
                    f"m=main, msg=GChat notification was not sent. error={e}"
                )
        return

    load_dataframe_into_datalake(
        bucket,
        df,
        environment,
        table_name,
        dag_name,
        target_database_name=args.target_database_name,
        target_table_name=args.target_table_name,
    )


if __name__ == "__main__":
    main()
