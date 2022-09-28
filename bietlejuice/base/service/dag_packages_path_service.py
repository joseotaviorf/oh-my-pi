import os
from glob import glob
from os import path
from os.path import dirname

import boto3

from bietlejuice import BIETLEJUICE_PROJECT_ROOT
from bietlejuice.base import QUERIES_DATALAKE_PATH, DATA_QUALITY_TESTS_PATH
from bietlejuice.enums.dag_package_enum import DAGPackagesEnum
from dags import DAG_PACKAGES_ROOT

S3 = boto3.client("s3")


class DuplicateDAGException(Exception):
    # TODO move to base/airflow/exceptions when imports conflicts are resolved
    """Raises when a DAG is duplicated inside the repository"""


class DAGPackagesPathService:
    """
    Abstracts and centralizes path/directory manipulations related to the DAGs or its inner contents.
    """

    @staticmethod
    def _get_dag_package_path(dag_name):
        """
        Returns the DAG's path (considering it is inside the DAG Packages structure)

        The path returned does not contain trailing slash like `/dags/bla/foo`

        :param dag_name: the DAG name, that is expected to be unique in the entire platform
        :return: full DAG Package path
        """
        dag_folder = glob(f"{DAG_PACKAGES_ROOT}/**/{dag_name}", recursive=True)

        # Non-migrated DAGs (in bietlejuice module) or non-existent
        if not dag_folder:
            return None

        if len(dag_folder) > 1:
            raise DuplicateDAGException(
                f"There is more than one registry for the DAG, dag_name={dag_name}"
            )

        return dag_folder[0]

    @staticmethod
    def _is_dag_in_legacy_structure(dag_name: str) -> bool:
        """
        Returns the DAG's path (considering it is inside the legacy structure)

        The path returned does not contain trailing slash like `/dags/bla/foo`

        :param dag_name: the DAG name, that is expected to be unique in the entire platform
        :return: full legacy DAG path
        """

        dag_path = f"{BIETLEJUICE_PROJECT_ROOT}/dags/{dag_name}"
        return os.path.exists(dag_path)

    @staticmethod
    def _read_file_content_from_filesystem(file_path: str):
        """
        Open a file from the bietlejuice wheel (for Databricks) or GCS path (for Composer)

        :param file_path: absolute file path
        :return: file content
        :raises: RuntimeError
        """
        try:
            with open(file_path) as f:
                return f.read()
        except IOError as e:
            raise RuntimeError(
                f"m=_read_file_content_from_filesystem, file_name={file_path},"
                f" msg=File not found, error={e}"
            )

    @staticmethod
    def _read_file_from_s3(bucket_name: str, file_key: str):
        """
        Read a file from S3 based on Bucket and s3 file path.

        :return: file content.
        """
        data = S3.get_object(Bucket=bucket_name, Key=file_key)
        query = data["Body"].read().decode("utf-8")

        return query

    @staticmethod
    def get_dag_path(dag_name: str) -> str:
        """
        Gets the DAG's full path

        * Method used only in Composer *

        Finds the DAG path according to its location: inside the DAG Packages or in the legacy path (bietlejuice)
        :return: full DAG's parent path
        """
        dag_path = DAGPackagesPathService._get_dag_package_path(dag_name)
        if not dag_path:
            dag_path = f"{BIETLEJUICE_PROJECT_ROOT}/dags/{dag_name}"

        return dag_path

    @staticmethod
    def get_dag_parent_path(dag_name: str) -> str:
        """
        Gets the DAG's parent path

        * Method used only in Composer *

        Finds the DAG path according to its location: inside the DAG Packages or in the legacy path (bietlejuice)
        :return: full DAG's parent path
        """
        dag_path = DAGPackagesPathService._get_dag_package_path(dag_name)
        if dag_path:
            dag_parent_folder = dirname(dag_path)
        else:  # TODO: remove after DAG-Packages migration
            dag_parent_folder = f"{BIETLEJUICE_PROJECT_ROOT}/dags"

        return dag_parent_folder

    @staticmethod
    def get_query_file_content_in_spark_jobs(
        dag_name: str, table_name: str, layer: str = "", intermediate_path: str = ""
    ):
        """
        Opens the SQL file according to the place it is stored (if it is in
         legacy path or in the DAGs packages)

        * Method used only in Databricks *

        :param dag_name:
        :param table_name:
        :param layer:
        :param intermediate_path:
        :return:
        """
        if DAGPackagesPathService._is_dag_in_legacy_structure(dag_name):
            # TODO: remove after DAG-Packages migration
            sql_file_path = path.join(
                f"{QUERIES_DATALAKE_PATH}/{dag_name}/{layer}",
                intermediate_path,
                f"{table_name}.sql",
            )
            query_content = DAGPackagesPathService._read_file_content_from_filesystem(
                sql_file_path
            )
        else:
            sql_file_relative_path = path.join(
                f"queries/{dag_name}/{layer}", intermediate_path, f"{table_name}.sql"
            )
            sql_file_path = path.join(
                DAGPackagesEnum.S3_DAG_PACKAGES_FILES_PATH, sql_file_relative_path
            )
            query_content = DAGPackagesPathService._read_file_from_s3(
                bucket_name=DAGPackagesEnum.DATABRICKS_FILES_BUCKET,
                file_key=sql_file_path,
            )

        if not query_content:
            raise FileNotFoundError(
                f"Query file was not found or is empty, dag_name={dag_name}, sql_file_path={sql_file_path}"
            )

        return query_content

    @staticmethod
    def get_data_quality_file_content_in_spark_jobs(
        dag_name: str, table_name: str, layer: str, intermediate_path: str
    ):
        """
        Opens the Data Quality file according to the place it is stored (if it is in
         legacy path or in the DAGs packages)

        * Method used only in Databricks *

        :param dag_name:
        :param table_name:
        :param layer:
        :param intermediate_path:
        :return:
        """
        if DAGPackagesPathService._is_dag_in_legacy_structure(dag_name):
            # TODO: remove after DAG-Packages migration
            data_quality_file_path = path.join(
                f"{DATA_QUALITY_TESTS_PATH}/{dag_name}/{layer}",
                intermediate_path,
                f"{table_name}.sql",
            )
            data_quality_content = DAGPackagesPathService._read_file_content_from_filesystem(
                data_quality_file_path
            )
        else:
            data_quality_relative_path = path.join(
                f"data_quality/{dag_name}/{layer}",
                intermediate_path,
                f"{table_name}.yml",
            )
            data_quality_file_path = path.join(
                DAGPackagesEnum.S3_DAG_PACKAGES_FILES_PATH, data_quality_relative_path
            )

            try:
                data_quality_content = DAGPackagesPathService._read_file_from_s3(
                    bucket_name=DAGPackagesEnum.DATABRICKS_FILES_BUCKET,
                    file_key=data_quality_file_path,
                )
            except Exception as e:
                if "NoSuchKey" in str(e):
                    data_quality_content = DAGPackagesPathService._read_file_from_s3(
                        bucket_name=DAGPackagesEnum.DATABRICKS_FILES_BUCKET,
                        file_key=data_quality_file_path.replace("yml", "yaml"),
                    )
                else:
                    raise e

        if not data_quality_content:
            raise FileNotFoundError(
                f"Data quality file was not found, dag_name={dag_name}, data_quality_file_path={data_quality_file_path}"
            )

        return data_quality_content
