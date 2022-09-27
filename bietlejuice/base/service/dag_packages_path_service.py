import os
import boto3
from glob import glob
from os.path import dirname

from bietlejuice import BIETLEJUICE_PROJECT_ROOT
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

        # Non-migrated DAGs (in bietlejuice module)
        if not dag_folder:
            return None

        if len(dag_folder) > 1:
            raise DuplicateDAGException(
                f"There is more than one registry for the DAG, dag_name={dag_name}"
            )

        return dag_folder[0]

    @staticmethod
    def get_dag_path(dag_name: str) -> str:
        """
        Gets the DAG's full path

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
    def get_legacy_dag_path(dag_name: str) -> str:
        """
        Returns the DAG path if the DAG exists in legacy structure (bietlejuice) and if doesn't return None.

        :return: DAG path if exists.
        """

        dag_path = f"{BIETLEJUICE_PROJECT_ROOT}/dags/{dag_name}"
        if not os.path.exists(dag_path):
            dag_path = None

        return dag_path

    @staticmethod
    def get_query_file_path_from_legacy_structure(
        dag_legacy_path: str, dag_name: str, table_name: str, query_layer: str = ""
    ) -> str:
        """
        Get query file path from legacy structure (bietlejuice).
        :return: full query path.
        """
        dag_query_path = glob(
            f"{BIETLEJUICE_PROJECT_ROOT}/db/*/queries/{dag_name}/{query_layer}/**/{table_name}.sql",
            recursive=True,
        )
        if not dag_query_path:
            raise FileNotFoundError(
                f"File was not found, dag_name={dag_name}, file_name={table_name}, dag_path={dag_legacy_path}"
            )

        return dag_query_path[0]

    @staticmethod
    def get_data_quality_file_path_from_legacy_structure(
        dag_name: str, file_name: str, data_quality_layer: str = ""
    ) -> str:
        """
        Get data quality file path from legacy structure (bietlejuice).
        :return: full data quality path.
        """
        dag_data_quality_path = glob(
            f"{BIETLEJUICE_PROJECT_ROOT}/db/*/data_quality/{dag_name}/{data_quality_layer}/**/{file_name}.yml",
            recursive=True,
        )
        if not dag_data_quality_path:
            raise FileNotFoundError(
                f"File was not found, dag_name={dag_name}, file_name={file_name}"
            )

        return dag_data_quality_path[0]

    @staticmethod
    def mount_data_quality_path_from_dag_packages(
        dag_name: str, file_name: str, data_quality_layer: str = ""
    ):
        data_quality_file_path = (
            f"data_quality/{dag_name}/{data_quality_layer}/{file_name}.yml"
        ).replace(
            "//", "/"
        )  # TODO: considerer other cases (line, mode)

        return data_quality_file_path

    @staticmethod
    def mount_query_path_from_dag_packages(
        dag_name: str,
        table_name: str,
        query_layer: str = "",
        intermediate_path: str = "",
    ):
        query_file_path = (
            f"queries/{dag_name}/{query_layer}/{intermediate_path}/{table_name}.sql"
        ).replace(
            "//", "/"
        )  # TODO: considerer other cases (line, mode)

        return query_file_path

    @staticmethod
    def get_dag_query_file_content(
        dag_name: str,
        table_name: str,
        query_layer: str = "",
        intermediate_path: str = "",
    ):
        dag_legacy_path = DAGPackagesPathService.get_legacy_dag_path(dag_name)
        if dag_legacy_path:  # TODO: remove after DAG-Packages migration
            dag_query_path = DAGPackagesPathService.get_query_file_path_from_legacy_structure(
                dag_legacy_path=dag_legacy_path,
                dag_name=dag_name,
                table_name=table_name,
                query_layer=query_layer,
            )
            query_content = DAGPackagesPathService.get_file_from_legacy_dag_path(
                dag_query_path
            )
        else:
            query_file_path = DAGPackagesPathService.mount_query_path_from_dag_packages(
                dag_name=dag_name,
                table_name=table_name,
                query_layer=query_layer,
                intermediate_path=intermediate_path,
            )
            query_content = DAGPackagesPathService.read_dag_file_from_s3(
                bucket_name=DAGPackagesEnum.S3_DAG_PACKAGES_FILES_BUCKET_OLD,
                s3_file_path=f"{DAGPackagesEnum.S3_DAG_PACKAGES_FILES_PATH}/{query_file_path}".replace(
                    "//", "/"
                ),
            )

        if not query_content:
            raise FileNotFoundError(
                f"Query file was not found, dag_name={dag_name}, file_name={table_name}"
            )

        return query_content

    @staticmethod
    def get_dag_data_quality_file_content(
        dag_name: str, file_name: str, data_quality_layer: str = ""
    ):
        dag_legacy_path = DAGPackagesPathService.get_legacy_dag_path(dag_name)
        if dag_legacy_path:  # TODO: remove after DAG-Packages migration
            dag_data_quality_path = DAGPackagesPathService.get_data_quality_file_path_from_legacy_structure(
                dag_name=dag_name,
                file_name=file_name,
                data_quality_layer=data_quality_layer,
            )
            data_quality_content = DAGPackagesPathService.get_file_from_legacy_dag_path(
                legacy_file_path=dag_data_quality_path
            )
        else:
            data_quality_file_path = DAGPackagesPathService.mount_data_quality_path_from_dag_packages(
                dag_name=dag_name,
                file_name=file_name,
                data_quality_layer=data_quality_layer,
            )
            try:
                data_quality_content = DAGPackagesPathService.read_dag_file_from_s3(
                    bucket_name=DAGPackagesEnum.S3_DAG_PACKAGES_FILES_BUCKET_OLD,
                    s3_file_path=f"{DAGPackagesEnum.S3_DAG_PACKAGES_FILES_PATH}/{data_quality_file_path}".replace(
                        "//", "/"
                    ),
                )
            except Exception as e:
                if "NoSuchKey" in str(e):
                    data_quality_file_path = data_quality_file_path.replace(
                        "yml", "yaml"
                    )
                    data_quality_content = DAGPackagesPathService.read_dag_file_from_s3(
                        bucket_name=DAGPackagesEnum.S3_DAG_PACKAGES_FILES_BUCKET_OLD,
                        s3_file_path=f"{DAGPackagesEnum.S3_DAG_PACKAGES_FILES_PATH}/{data_quality_file_path}".replace(
                            "//", "/"
                        ),
                    )
                else:
                    raise e

        if not data_quality_content:
            raise FileNotFoundError(
                f"Data quality file was not found, dag_name={dag_name}, file_name={file_name}"
            )

        return data_quality_content

    @staticmethod
    def get_file_from_legacy_dag_path(legacy_file_path: str):
        """
        Open a file from the bietlejuice wheel

        :param file_name: absolute file path
        :return: file content
        :raises: RuntimeError
        """
        try:
            with open(legacy_file_path) as f:
                return f.read()
        except IOError as e:
            raise RuntimeError(
                f"m=get_query_from_legacy_dag_path, file_name={legacy_file_path}, msg=file not found, error={e}"
            )

    @staticmethod
    def read_dag_file_from_s3(bucket_name: str, s3_file_path: str):
        """
        Read a file from S3.

        Finds the file on S3 based on Bucket and s3 file path.
        :return: file content.
        """
        data = S3.get_object(Bucket=bucket_name, Key=s3_file_path)
        query = data["Body"].read().decode("utf-8")

        return query
