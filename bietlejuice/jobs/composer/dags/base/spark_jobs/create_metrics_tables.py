import json
import boto3

from argparse import ArgumentParser
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseDBUtils, BaseSparkContext
from bietlejuice.jobs.composer.services import FileService, S3Service
from bietlejuice.jobs.composer.base.db import DatabaseClientFactory

JOB_NAME = "create_metrics_tables"


def get_query(file_path):
    """
    Get the query from a file storaged locally or on s3.
    :param file_path: string with the path were the file is located
    :return string with the query content
    """
    if file_path.startswith("s3://"):
        s3_service = S3Service(boto3.resource("s3"))
        return s3_service.read_file(file_path)
    else:
        return FileService.get_query_from_file_name(file_path)


def create_table(dw_schema, file_path, database_connection):
    """
    Create a table on DW using CTAS approach.
    :param dw_schema: dw schema name where the table will be created
    :type dw_schema: str
    :param file_path: path were the file is located
    :type file_path: str
    :param database_connection: dict with db connection credentials
    :type database_connection: dict
    :return None
    """
    logger = QuintoAndarLogger(JOB_NAME)

    table_name = file_path.replace(".sql", "").split("/")[-1]
    query = get_query(file_path)
    database_client = DatabaseClientFactory.get_client(database_connection["dbtype"])(
        dbname=database_connection["db"],
        host=database_connection["host"],
        port=database_connection["port"],
        user=database_connection["user"],
        password=database_connection["pwd"],
        keepalives_idle=200,
    )

    table_exists = database_client.get_records(
        f"""
            SELECT
                1
            FROM
                information_schema.tables t
            WHERE
                t.table_schema = '{dw_schema}'
                AND t.table_name = '{table_name}'
        """
    )

    if table_exists:
        alter_table_query = f"""
            ALTER TABLE {dw_schema}.{table_name} RENAME TO {table_name}_old;
            ALTER TABLE {dw_schema}.{table_name}_new RENAME TO {table_name};
        """
    else:
        alter_table_query = (
            f"ALTER TABLE {dw_schema}.{table_name}_new RENAME TO {table_name};"
        )

    logger.info("m=create_table, msg=executing query {0}".format(query))

    database_client.drop_table(dw_schema, f"{table_name}_new", if_exists=True)
    database_client.drop_table(dw_schema, f"{table_name}_old", if_exists=True)
    database_client.create_table_from_select(dw_schema, f"{table_name}_new", query)
    database_client.run(alter_table_query)
    database_client.drop_table(dw_schema, f"{table_name}_old", if_exists=True)


def start_spark_job(dw_schema, files_paths, database_connection):
    """
    Orchestrate the spark job, receive a list of SQL files, and parallelize the CTAS creation on the cluster.

    :param dw_schema: dw schema name where the table will be created
    :type dw_schema: str
    :param files_paths: list of paths where query files are located
    :type files_paths: list
    :param database_connection: dict with db connection credentials
    :type database_connection: dict
    :return None
    """
    sc = BaseSparkContext.sc
    rdd = sc.parallelize(files_paths)
    rdd.map(
        lambda file_path: create_table(dw_schema, file_path, database_connection)
    ).collect()


if __name__ == "__main__":
    logger = QuintoAndarLogger(JOB_NAME)

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dw_schema", type=str, help="dw schema")
    parser.add_argument("database", type=str, help="database")
    parser.add_argument(
        "s3_folder_path",
        type=str,
        help="full path to the target folder in s3, ex: s3://bucket-name/path/to/folder/",
    )

    args = parser.parse_args()
    dw_schema = args.dw_schema
    dataabse_conn_enum_key = args.database
    s3_folder_path = args.s3_folder_path

    s3_service = S3Service(boto3.resource("s3"))
    files_paths = s3_service.list_sql_files(s3_folder_path)

    logger.info(
        f"m={JOB_NAME}, dw_schema={dw_schema}, s3_folder_path={s3_folder_path}"
        + f"file_path={files_paths}, msg=Job execution started"
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    database_connection = json.loads(
        dbutils.secrets.get("quintoandar", dataabse_conn_enum_key)
    )
    start_spark_job(dw_schema, files_paths, database_connection)
