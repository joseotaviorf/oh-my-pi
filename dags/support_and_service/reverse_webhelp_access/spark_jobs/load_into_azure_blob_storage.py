import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    is_validation_run,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_into_azure_blob_storage"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
dbutils = BaseDBUtils().get_dbutils()


def main():
    job_args = parse_arguments()

    if is_validation_run(
        job_args["target_database_name"],
        job_args["target_table_name"],
    ):
        logger.info(
            f"m={JOB_NAME}, msg=Skipping reverse Azure export in cluster validation mode"
        )
        return

    logger.info(
        f"""m=__main__, environment={job_args["environment"]}, dag_name={job_args["dag_name"]}, database_name={job_args["database_name"]},
        table_name={job_args["table_name"]}, azure_container_name={job_args["azure_container_name"]}, execution_date={job_args["execution_date"]}
        table_context={job_args["table_context"]}"""
    )

    storage_account_name, storage_account_access_key = get_azure_credentials()
    spark.conf.set(
        f"fs.azure.account.key.{storage_account_name}.blob.core.windows.net",
        f"{storage_account_access_key}",
    )
    blob_storage_path = f"wasbs://{job_args['azure_container_name']}@{storage_account_name}.blob.core.windows.net/"

    load_table_in_azure_blob_storage(
        job_args["dag_name"],
        job_args["database_name"],
        job_args["table_name"],
        blob_storage_path,
        job_args["table_context"],
        job_args["execution_date"],
    )


def parse_arguments() -> dict:
    """
    Parse the arguments passed to the job.
    """

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("dag_name")
    parser.add_argument("database_name")
    parser.add_argument("table_name")
    parser.add_argument(
        "execution_date", help="Date of the execution in the format YYYY-MM-DD"
    )
    parser.add_argument("table_context")
    add_validation_target_args(parser)

    args = parser.parse_args()

    config_service = ConfigurationService(args.dag_name)
    azure_container_name = config_service.get_config("azure_container_name")

    return {
        "environment": args.env,
        "dag_name": args.dag_name,
        "database_name": args.database_name,
        "table_name": args.table_name,
        "azure_container_name": azure_container_name,
        "table_context": args.table_context,
        "execution_date": datetime.fromisoformat(args.execution_date),
        "target_database_name": args.target_database_name,
        "target_table_name": args.target_table_name,
    }


def get_azure_credentials():
    DATABRICKS_SCOPE = "quintoandar"

    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key="AZURE_WEBHELP")
    credentials = json.loads(json_credentials)

    return credentials["storage_account_name"], credentials[
        "storage_account_access_key"
    ]


PARTITION_COLUMNS = ("year", "month", "day")


def _configure_azure_parquet_write() -> None:
    """Use the standard Hadoop committer for WASBS writes.

    EMR's ``EmrOptimizedSparkSqlParquetOutputCommitter`` cleanup fails on Azure
    Blob Storage with ``StorageException: non-empty directory``.
    """
    spark.conf.set(
        "spark.sql.sources.commitProtocolClass",
        "org.apache.spark.sql.execution.datasources.SQLHadoopMapReduceCommitProtocol",
    )
    spark.conf.set(
        "spark.sql.parquet.output.committer.class",
        "org.apache.parquet.hadoop.ParquetOutputCommitter",
    )


def _partition_output_path(base_path: str, execution_date: datetime) -> str:
    return (
        f"{base_path}year={execution_date.year}/"
        f"month={execution_date.month}/day={execution_date.day}/"
    )


def _hadoop_fs(path: str):
    hadoop_conf = spark.sparkContext._jsc.hadoopConfiguration()
    fs_uri = spark._jvm.java.net.URI(path)
    return spark._jvm.org.apache.hadoop.fs.FileSystem.get(fs_uri, hadoop_conf)


def _delete_wasbs_tree(fs, hadoop_path) -> None:
    status = fs.getFileStatus(hadoop_path)
    if status.isDirectory():
        for child in fs.listStatus(hadoop_path):
            _delete_wasbs_tree(fs, child.getPath())
    fs.delete(hadoop_path, False)


def _replace_execution_date_partition(path: str) -> None:
    """Remove only this execution date's folder so a re-run replaces that day.

    WASBS cannot recursively delete a non-empty directory in one call, which is
    what Spark overwrite uses. Children-first delete is the equivalent of the
    original ``partitionOverwriteMode=dynamic`` for a single day.
    """
    fs = _hadoop_fs(path)
    hadoop_path = spark._jvm.org.apache.hadoop.fs.Path(path)
    if not fs.exists(hadoop_path):
        return
    logger.info(
        f"m=_replace_execution_date_partition, path={path}, msg=Deleting day partition"
    )
    _delete_wasbs_tree(fs, hadoop_path)


def load_table_in_azure_blob_storage(
    dag_name: str,
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
        path_to_save = (
            f"{blob_storage_path}/quinto_andar/{table_context}/to_webhelp_{table_name}/"
        )
    else:
        path_to_save = f"{blob_storage_path}/quinto_andar/to_webhelp_{table_name}/"

    partition_path = _partition_output_path(path_to_save, execution_date)
    if df.rdd.isEmpty():
        logger.info(
            f"m=load_table_in_azure_blob_storage, table_name={table_name}, "
            f"path={partition_path}, msg=No rows for execution date; keeping existing Azure partition"
        )
        return

    drop_cols = [col for col in PARTITION_COLUMNS if col in df.columns]
    _replace_execution_date_partition(partition_path)
    _configure_azure_parquet_write()
    df.drop(*drop_cols).coalesce(1).write.mode("overwrite").format("parquet").save(
        partition_path
    )


if __name__ == "__main__":
    main()
