import json
import logging
from argparse import ArgumentParser
from datetime import datetime
from itertools import chain

import boto3
import requests
from botocore.credentials import RefreshableCredentials
from pyspark.sql.types import StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services import S3Service
from bietlejuice.services.metastore_services import SparkMetastoreService


class LabelStudioConnectionSync:
    """
    This class contains methods to synchronize the data contained in LabelStudio
    with a pre-configured connection to Storage S3.
    """

    def __init__(self, api_credentials, aws_credentials, bucket_name):
        self.api_token = api_credentials["user_token"]
        self.api_endpoint = api_credentials["api_endpoint"]

        self.api_headers = {"Authorization": f"Token {self.api_token}"}

        self.bucket_name = bucket_name

        self.aws_session_token = aws_credentials.get_frozen_credentials().token
        self.aws_access_key_id = aws_credentials.get_frozen_credentials().access_key
        self.aws_secret_access_key = aws_credentials.get_frozen_credentials().secret_key

    def refresh_aws_credentials(self, s3_session, refresh_s3_credentials):
        """
        This method uptade the Storage S3 credentials.
        @param aws_credentials: dict. Storage S3 token, acess key and secret acess key.
        @param s3_session: boto3 session.
        @param refresh_s3_credentials: type callable. This method will return a dict with
        expiry time and credentials of a boto3 session
        """
        aws_credentials = RefreshableCredentials.create_from_metadata(
            metadata=refresh_s3_credentials(s3_session),
            refresh_using=refresh_s3_credentials,
            method="sts-assume-role",
        )
        self.aws_session_token = aws_credentials.get_frozen_credentials().token
        self.aws_access_key_id = aws_credentials.get_frozen_credentials().access_key
        self.aws_secret_access_key = aws_credentials.get_frozen_credentials().secret_key

    def get_projects_info(self):
        """
        This method returns a list of dicts for each project in Label Studio
        @return: list
        """
        response = requests.get(
            f"{self.api_endpoint}projects", headers=self.api_headers
        )
        if response:
            resp = json.loads(response.content)
            results = resp["results"]
            while resp["next"]:
                response = requests.get(resp["next"], headers=self.api_headers)
                resp = json.loads(response.content)
                results.extend(resp["results"])
            return results
        else:
            raise Exception(
                f"""m=__get_project_id, status_code={response.status_code},
                response_content={response.content}
                msg=The API returned an empty response body."""
            )

    def sync_data_s3_storage(self, project_id):
        """
        The method syncs the LabelStudio project data in S3 storage.
        @param project_id: project code in the LabelStudio environment.
        """
        self.__delete_all_project_connections(project_id)

        storage_id = self.__create_connection_s3_storage(project_id)

        params = {"project": project_id, "use_blob_urls": False}
        response = requests.post(
            f"{self.api_endpoint}storages/export/s3/{storage_id}/sync",
            headers=self.api_headers,
            params=params,
        )

        self.__delete_connection_s3_storage(storage_id, project_id)

        if not response.ok and response.status_code != 504:
            raise Exception(
                f"""m=sync_data_s3_storage, project_id={project_id}, status_code={response.status_code}
                msg=Unable to sync data in storage. response_content={response.content}"""
            )

    def project_is_updated(self, project, execution_date):
        """
        This method verify if LabelStudio project went updated.
        @param project: informations about Label Studio project.
        @param execution_date: DAG execution datetime.
        @return: boolean
        """
        project_id = project.get("id")
        last_execution_date = (datetime.strptime(execution_date, "%Y-%m-%d")).date()

        response = requests.get(
            f"{self.api_endpoint}projects/{project_id}/tasks", headers=self.api_headers
        )

        if not response.ok:
            raise Exception(
                f"""m=project_is_updated, project_id={project_id}, status_code={response.status_code}
                msg=There seems to be some problem with the LabelStudio connection.
                response_content={response.content}"""
            )

        elif list(
            filter(
                lambda task: self.__task_is_updated(task, last_execution_date),
                json.loads(response.content),
            )
        ):
            return project

    @staticmethod
    def __task_is_updated(task, execution_date):
        """
        This method verify if project task went updated.
        @param task: informations about a project task.
        @param execution_date: DAG execution date.
        @return: boolean
        """
        annotations = task.get("annotations")
        if list(
            filter(
                lambda task: datetime.strptime(
                    task.get("updated_at"), "%Y-%m-%dT%H:%M:%S.%fZ"
                ).date()
                >= execution_date,
                annotations,
            )
        ):
            return task

    def __create_connection_s3_storage(self, project_id):
        """
        This method create a connection between the LabelStudio project and the Storage S3.
        @param project_id: project ID code generated by Label Studio.
        @return: json
        """
        payloads = {
            "project": project_id,
            "bucket": self.bucket_name,
            "prefix": f"raw/label_studio/sync/{project_id}",
            "aws_access_key_id": self.aws_access_key_id,
            "aws_secret_access_key": self.aws_secret_access_key,
            "aws_session_token": self.aws_session_token,
        }
        response = requests.post(
            f"{self.api_endpoint}storages/export/s3", payloads, headers=self.api_headers
        )
        if response.ok:
            return json.loads(response.content).get("id")
        else:
            raise Exception(
                f"""m=__create_connection_s3_storage, project_id={project_id},
                status_code={response.status_code}, response_content={response.content}
                msg=There seems to be some problem with the s3 storage connection settings."""
            )

    def __delete_connection_s3_storage(self, storage_id, project_id):
        """
        This method delete a connection between the LabelStudio project and the Storage S3.
        @param storage_id: storage connection ID code generated by Label Studio.
        """
        response = requests.delete(
            f"{self.api_endpoint}storages/export/s3/{storage_id}",
            headers=self.api_headers,
        )
        if not response.ok:
            raise Exception(
                f"""m=__delete_connection_s3_storage, storage_id={storage_id}, project_id={project_id},
                status_code={response.status_code}, response_content={response.content}
                msg=There seems to be some problem with the s3 storage connection settings."""
            )

    def __delete_all_project_connections(self, project_id):
        """
        This method delete all old s3 connections of a Label Studio project and
        avoid duplicates creation.
        """
        payloads = {"project": project_id}
        response = requests.get(
            f"{self.api_endpoint}storages/export/s3",
            params=payloads,
            headers=self.api_headers,
        )
        if response.ok:
            connections_info = json.loads(response.content)

            map(
                lambda connection_info: self.__delete_connection_s3_storage(
                    connection_info.get("id"), project_id
                ),
                connections_info,
            )
        else:
            raise Exception(
                f"""m=__delete_all_project_connections, project_id={project_id},
                status_code={response.status_code}, response_content={response.content}
                msg=There seems to be some problem with the s3 storage connection settings."""
            )


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
