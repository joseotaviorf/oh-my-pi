import boto3
import json
import logging

from argparse import ArgumentParser
from itertools import chain
from pyspark.sql.types import StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.dags.label_studio.label_studio_connection_sync import (
    LabelStudioConnectionSync,
)
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services import S3Service
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService


def refresh_s3_credentials(s3_session):
    """
    This method create new boto3 credentails.
    @return: dict
    """
    credentials = s3_session.get_credentials()
    return dict(
        access_key=credentials._access_key,
        secret_key=credentials._secret_key,
        token=credentials._token,
        expiry_time=credentials._expiry_time.isoformat(),
    )


def _read_project_data(file_path, project_id, project_name):
    """
    This method return a s3 object data.
    @param file_path: str. S3 file path.
    @param project_id: project code in the LabelStudio environment.
    @return: str
    """
    if file_path.split("/")[-1]:
        s3_service = S3Service(boto3.resource("s3"))
        content = json.loads(s3_service.read_file(file_path))
        content["project_id"] = project_id
        content["project_name"] = project_name
        return json.dumps(content)
    else:
        return {}


def _create_or_replace_empty_folder(s3_service, s3_folder_path):
    """
    Creates a new empty partition in the s3 bucket or, if the partition
    already exists, deletes existing files.
    @param s3_service: S3Service.
    @param s3_folder_path: full path to the target folder in s3,
    ex: "s3://bucket-name/path/to/folder/"
    """
    files_path_list = s3_service.list_objects(s3_folder_path)

    if not files_path_list:
        s3_service.create_empty_object(f"{s3_folder_path}/")
    else:
        map(lambda file_path: s3_service.delete_object(file_path), files_path_list)


def _get_project_data(project_details):
    """
    This method return the LabelStudio project data.
    @param project_details: json. Project details: name, id, creation date, etc.
    @return: json.
    """
    project_id = project_details.get("id")
    project_name = project_details.get("title")
    s3_folder_path = f"{database_location}sync/{project_id}"

    s3_service = S3Service(boto3.resource("s3"))

    _create_or_replace_empty_folder(s3_service, s3_folder_path)

    # uptade the boto3 session credentials
    s3_session = boto3.Session()

    label_studio_connection_sync.refresh_aws_credentials(
        s3_session, refresh_s3_credentials
    )

    # sync labelstudio data
    label_studio_connection_sync.sync_data_s3_storage(project_id)

    files_path_list = s3_service.list_objects(s3_folder_path)

    return list(
        map(
            lambda file_path: _read_project_data(file_path, project_id, project_name),
            files_path_list,
        )
    )


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "add_partitions_to_raw_tables"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name", help="raw table name")
    parser.add_argument("data_schema")
    parser.add_argument("execution_date")
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    dt_execution = args.execution_date

    schema = StructType.fromJson(json.loads(args.data_schema))
    partition_cols = ["project_id"]

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket},
            msg=Starting spark job...
        """
    )

    # Initializing clients
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    s3_service = S3Service(boto3.resource("s3"))

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )
    database_name = datalake_info["db_raw_databricks"]
    database_location = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    # Label Studio
    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.LABEL_STUDIO
    )
    credentials = json.loads(json_credentials)

    aws_credentials = boto3.Session().get_credentials()

    label_studio_connection_sync = LabelStudioConnectionSync(
        api_credentials=credentials,
        aws_credentials=aws_credentials,
        bucket_name=database_location.split("/")[2],
    )

    # get updated projects from LabelStudio
    projects_info = spark_client.conn.sparkContext.parallelize(
        label_studio_connection_sync.get_projects_info()
    )
    projects_updated = projects_info.filter(
        lambda project: label_studio_connection_sync.project_is_updated(
            project, dt_execution
        )
    )

    # get data projects from LabelStudio
    projects_updated = projects_updated.map(lambda project: _get_project_data(project))
    projects_updated = projects_updated.flatMap(lambda x: chain(x)).filter(lambda x: x)

    if not projects_updated.isEmpty():
        df = spark_client.conn.read.schema(schema).json(projects_updated)

        s3_loader = S3Loader()
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
        )

        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            partitions=partition_cols,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=partition_cols,
        )
