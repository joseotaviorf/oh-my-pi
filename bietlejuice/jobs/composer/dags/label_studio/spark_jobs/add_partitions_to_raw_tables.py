import boto3
import json
import logging
import re

from argparse import ArgumentParser
from botocore.credentials import RefreshableCredentials
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.dags.label_studio.label_studio_connection_sync import (
    LabelStudioConnectionSync,
)
from bietlejuice.jobs.composer.formatters import StringFormatter
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services import S3Service
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService


def __clean_html(raw_html):
    """
    Clears html characters and emoticons from a string.
    @param raw_html: string to be transformed.
    @return: string.
    """
    emoji_pattern = re.compile(
        "["
        "\U0001F600-\U0001F64F"  # emoticons
        "\U0001F300-\U0001F5FF"  # symbols & pictographs
        "\U0001F680-\U0001F6FF"  # transport & map symbols
        "\U0001F1E0-\U0001F1FF"  # flags (iOS)
        "]+",
        flags=re.UNICODE,
    )
    cleanr = re.compile("<.*?>")
    cleantext = re.sub(cleanr, "", emoji_pattern.sub(r"", raw_html))
    return cleantext


def __flatten_json(old_json, new_json={}, name=""):
    """
    Transform nested json terms into plain string.
    @param old_json: json to be cleared.
    @param new_json: json. Where the transformations will be appended.
    @param name: str. Name that will be appended to the old key name
    @return: json
    """
    for key in old_json:
        if type(old_json[key]) == dict:
            new_json = __flatten_json(old_json[key], new_json, key)
        elif name:
            new_json[f"{key}_{name}"] = __clean_html(str(old_json[key]))
        else:
            new_json[f"{key}"] = __clean_html(str(old_json[key]))
    return new_json


def __filter_data_files(files_path_list):
    """
    Filters all files and excludes surplus (non-data files).
    @param files_path_list: list of all the objects discovered under the folder.
    """
    ignored_files_prefix = ["success", "commit"]
    for file_path in files_path_list[1:]:
        if not any(prefix in file_path.lower() for prefix in ignored_files_prefix):
            return file_path


def __delete_objects(bucket_name, files_path_list):
    """
    Deletes all files from an s3 bucket folder.
    @param bucket_name: str. S3 bucket name.
    @param s3_folder_path: list of all the objects discovered under the folder.
    """
    for file_path in files_path_list:
        s3_service.s3_resource.Object(bucket_name, file_path).delete()


def __create_folder(bucket_name, objects_filter):
    """
    Create a folder in an s3 bucket.
    @param bucket_name: str. S3 bucket name.
    @param objects_filter: str. Folder prefix to be created in S3 bucket.
    """
    boto3.client("s3").put_object(Bucket=bucket_name, Key=(objects_filter + "/"))


def __verify_folder_exists(s3_service, s3_folder_path):
    """
    Checks if the project folder exists in the s3 bucket.
    @param s3_service: S3Service.
    @param s3_folder_path: full path to the target folder in s3, ex: "s3://bucket-name/path/to/folder/"
    """
    bucket_name, objects_filter = s3_service._split_s3_path(s3_folder_path)

    files_path_list = [
        obj.key
        for obj in s3_service.s3_resource.Bucket(bucket_name).objects.filter(
            Prefix=objects_filter + "/"
        )
    ][1:]

    if not files_path_list:
        __create_folder(bucket_name, objects_filter)
    else:
        __delete_objects(bucket_name, files_path_list[1:])


def __refresh_aws_credentials():
    """
    This method uptade the boto3 session credentials.
    @return: dict
    """
    credentials = boto3.Session().get_credentials()
    return dict(
        access_key=credentials._access_key,
        secret_key=credentials._secret_key,
        token=credentials._token,
        expiry_time=credentials._expiry_time.isoformat(),
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
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name

    config_service = ConfigurationService(dag_name=source)

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
        api_token=credentials["user_token"],
        config_service=config_service,
        aws_credentials=aws_credentials.get_frozen_credentials(),
        bucket_name=database_location.split("/")[2],
    )

    projects_info = label_studio_connection_sync.get_projects_info()
    files_content = []

    for project in projects_info:
        project_name = StringFormatter.set_alphanumeric_snake_case(project.get("title"))
        s3_folder_path = f"{database_location}sync/{project_name}"

        __verify_folder_exists(s3_service, s3_folder_path)

        if aws_credentials.refresh_needed():
            aws_credentials = RefreshableCredentials.create_from_metadata(
                metadata=__refresh_aws_credentials(),
                refresh_using=__refresh_aws_credentials,
                method="sts-assume-role",
            )
            label_studio_connection_sync.refresh_aws_credentials(
                aws_credentials=aws_credentials.get_frozen_credentials()
            )

        # sync labelstudio data
        label_studio_connection_sync.sync_data_s3_storage(
            project_id=project.get("id"), project_name=project_name
        )

        files_path_list = list(
            filter(__filter_data_files, s3_service.list_objects(s3_folder_path))
        )

        parse_column = config_service.get_config("parse_column")
        for file_path in files_path_list[1:]:
            content = json.loads(s3_service.read_file(file_path))
            content["project_name"] = project_name
            if content.get(parse_column):
                content[parse_column] = __flatten_json(content[parse_column])
            files_content.append([content[key] for key in content.keys()])

    if files_content:
        schema = list(content.keys())
        df = spark_client.create_dataframe(data=files_content, schema=schema)

        # loaders
        s3_loader = S3Loader()
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
        )

        spark_metastore_loader.update_metastore(
            df, database_name, table_name, format_options, database_location
        )
    else:
        raise Exception(
            f"""m=__main__, table_name={table_name},
            msg=There is no data stored in this directory: {s3_folder_path}."""
        )
