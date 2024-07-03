import json
import logging
from argparse import ArgumentParser, Namespace

from bietlejuice.clients.db_clients.trino_client import TrinoClient
from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper

JOB_NAME = "register_delta_table"
DELTA_CATALOG = "delta"
logging.getLogger("py4j").setLevel(logging.ERROR)


def parse_args() -> Namespace:
    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("bucket", type=str)
    parser.add_argument("layer", type=str)
    parser.add_argument("schema", type=str)
    parser.add_argument("table_name", type=str)

    return parser.parse_args()


def get_trino_client() -> TrinoClient:
    """
    Retrieves the Trino client using the credentials from Databricks Utils. The catalog will point to DELTA_CATALOG.
    """
    trino_credentials = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.TRINO)
    )
    return TrinoClient(
        host=trino_credentials["host"],
        port=trino_credentials["port"],
        user=trino_credentials["user"],
        password=trino_credentials["pwd"],
        catalog=DELTA_CATALOG,
    )


def register_table(
    trino_client: TrinoClient, database_name: str, table_name: str, table_location: str
) -> None:
    """
    Registers the table in Trino. If the schema does not exist, it will be created.
    If the table already exists but in parquet instead of Delta, it will be dropped.
    """
    trino_client.run(f"CREATE SCHEMA IF NOT EXISTS {DELTA_CATALOG}.{database_name}")
    if trino_client.table_exists(database_name, table_name):
        table_ddl = trino_client.get_table_ddl(database_name, table_name)
        is_delta = f"{DELTA_CATALOG}.{database_name}.{table_name}" in table_ddl.replace("\"", "")
        if not is_delta:
            trino_client.drop_table(database_name, table_name)

    trino_client.register_table(
        schema_name=database_name, table_name=table_name, table_location=table_location
    )


if __name__ == "__main__":
    args = parse_args()
    bucket = args.bucket
    layer = LayerEnum(args.layer).value
    schema = args.schema
    table_name = args.table_name

    spark_ms = SparkMetastoreHelper(bucket, layer, schema, table_name, all_tables=False)

    trino_client = get_trino_client()
    table_location = f"{spark_ms.database_location}/{table_name}".replace(
        "s3://", "s3a://"
    )  # Required by Trino

    register_table(trino_client, spark_ms.spark_database_name, table_name, table_location)
