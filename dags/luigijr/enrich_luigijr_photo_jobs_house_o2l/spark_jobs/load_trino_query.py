import json
from argparse import ArgumentParser
from datetime import datetime

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper
from bietlejuice.base.validation.target_resolver import managed_table_fqn
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.pipeline.delta_table_loader_pipeline import DeltaTableLoaderPipeline

JOB_NAME = "load_trino_query"
TEMP_VIEW = "luigi_trino_result"
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn


def parse_args():
    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("bucket")
    parser.add_argument("layer")
    parser.add_argument("schema")
    parser.add_argument("dag_name")
    parser.add_argument("table_name")
    parser.add_argument("partitions")
    parser.add_argument("load_end_date")
    parser.add_argument(
        "--target-database-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
    )
    parser.add_argument(
        "--target-table-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
    )
    return parser.parse_args()


def main():
    args = parse_args()
    creds = json.loads(
        BaseDBUtils()
        .get_dbutils()
        .secrets.get(scope="quintoandar", key=DatabaseEnum.TRINO_LUIGI_MATERIALIZATION)
    )
    sql = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=args.dag_name, layer=args.layer, table_name=args.table_name
    )
    dt = datetime.strptime(args.load_end_date[:10], "%Y-%m-%d")
    # Spark's JDBC `query` option wraps this string as a single-line subquery
    # (`SELECT * FROM (sql) alias`). A trailing `--` line comment — common in
    # SQL copied from the Trino console/DBeaver — would otherwise swallow the
    # closing paren and alias, breaking the query. The trailing newline forces
    # the comment to end before the wrapper is appended.
    sql = sql.format(year=dt.year, month=dt.month, day=dt.day).strip() + "\n"

    # Trino classifies the JDBC driver's explicit PREPARE as DATA_DEFINITION.
    # The materialization service account is SELECT-only, so use EXECUTE
    # IMMEDIATE and let Trino classify the submitted SQL by its real type.
    df = (
        spark.read.format("jdbc")
        .option("driver", "io.trino.jdbc.TrinoDriver")
        .option(
            "url",
            f"jdbc:trino://{creds['host']}:{creds['port']}/delta"
            "?SSL=true&source=luigi-materialization&clientTags=luigi"
            "&explicitPrepare=false",
        )
        .option("user", creds["user"])
        .option("password", creds["pwd"])
        .option("query", sql)
        .option("fetchsize", 10000)
        .load()
    )
    df.createOrReplaceTempView(TEMP_VIEW)

    spark_ms = SparkMetastoreHelper(
        args.bucket, args.layer, args.schema, args.table_name, all_tables=False
    )
    database_name = spark_ms.spark_database_name
    database_location = spark_ms.database_location.replace("s3a://", "s3://")

    write_table_name = args.table_name
    target_database_name = database_name
    target_database_location = database_location
    if args.target_database_name and args.target_table_name:
        from bietlejuice.base.validation.target_resolver import (
            validation_database_location,
        )

        target_database_name = args.target_database_name
        write_table_name = args.target_table_name
        target_database_location = validation_database_location(
            args.bucket, database_name
        ).replace("s3a://", "s3://")

    privileges_table = managed_table_fqn(
        database_name,
        args.table_name,
        args.target_database_name,
        args.target_table_name,
    )

    DeltaTableLoaderPipeline(
        database_name=database_name,
        table_name=write_table_name,
        database_location=database_location,
        target_database_name=target_database_name,
        target_database_location=target_database_location,
        layer=args.layer,
        query=f"SELECT * FROM {TEMP_VIEW}",
        partitions=json.loads(args.partitions),
        query_template_params={},
        table_privileges=TablePrivileges.from_environment_default(privileges_table),
        spark=spark,
    ).run()


if __name__ == "__main__":
    from bietlejuice.base.spark.spark_session_factory import run_spark_entrypoint

    run_spark_entrypoint(main)
