import logging
import json
from datetime import datetime
from argparse import ArgumentParser
from typing import Tuple
from bietlejuice.base.spark import BaseDBUtils

from quintoandar_logger import QuintoAndarLogger


JOB_NAME = "load_into_azure_blob_storage"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def main():
    environment, source, database_name, table_name, azure_container_name, table_context, execution_date = (
        parse_arguments()
    )
    logger.info(
        f"""m=__main__, environment={environment}, source={source}, database_name={database_name},
        table_name={table_name}, azure_container_name={azure_container_name}, execution_date={execution_date}
        table_context={table_context}"""
    )

    storage_account_name, storage_account_access_key = get_azure_credentials()
    spark.conf.set(f"fs.azure.account.key.{storage_account_name}.blob.core.windows.net", f"{storage_account_access_key}")
    blob_storage_path = f"wasbs://{azure_container_name}@{storage_account_name}.blob.core.windows.net/"

    load_table_in_azure_blob_storage(
        source, database_name, table_name, blob_storage_path, table_context, execution_date
    )


def parse_arguments() -> Tuple[str, str, str, str, datetime]:
    """
    Parse the arguments passed to the job.
    Returns a tuple with the database name, table name, event type, ARN of the SNS topic and execution date.
    """

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("source")
    parser.add_argument("database_name")
    parser.add_argument("table_name")
    parser.add_argument(
        "execution_date", help="Date of the execution in the format YYYY-MM-DD"
    )
    parser.add_argument("table_context")
    parser.add_argument("azure_container_name")

    args = parser.parse_args()

    environment = args.env
    source = args.source
    database_name = args.database_name
    table_name = args.table_name
    execution_date = datetime.fromisoformat(args.execution_date)
    azure_container_name = args.azure_container_name
    table_context = args.table_context

    return environment, source, database_name, table_name, azure_container_name, table_context, execution_date

def get_azure_credentials():
    DATABRICKS_SCOPE = "quintoandar"
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key="AZURE_WEBHELP"
    )
    credentials = json.loads(json_credentials)

    return credentials['storage_account_name'], credentials['storage_account_access_key']

def load_table_in_azure_blob_storage(
    source: str,
    database_name: str,
    table_name: str,
    blob_storage_path: str,
    table_context: str,
    execution_date: datetime,
):
    """
    Load the table into Azure.
    """

    df = spark.sql(
        f"""
            SELECT 
                * 
            FROM 
                {database_name}.{table_name} 
            WHERE 
                year={execution_date.year} 
                AND month={execution_date.month} 
                AND day={execution_date.day}
        """
    )

    if table_context in ["cx", "services", "speech_analytics"]:
        path_to_save = f"{blob_storage_path}/quinto_andar/{table_context}/to_webhelp_{table_name}/"
    else:
        path_to_save = f"{blob_storage_path}/quinto_andar/to_webhelp_{table_name}/"

    df.coalesce(1) \
        .write.partitionBy('year', 'month', 'day') \
        .mode('overwrite') \
        .format('parquet') \
        .option("partitionOverwriteMode", "dynamic") \
        .save(path_to_save)

if __name__ == "__main__":
    main()
