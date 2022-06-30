import requests
import json

from botocore.credentials import RefreshableCredentials
from datetime import datetime


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
        This method returns projects of the Label Studio.
        @return: json
        """
        response = requests.get(
            f"{self.api_endpoint}projects", headers=self.api_headers
        )
        if response:
            return json.loads(response.content)
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
