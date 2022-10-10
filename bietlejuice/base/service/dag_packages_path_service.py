import os
import re
from glob import glob
from os import path
from os.path import dirname, isfile

import boto3
from hierarchical_conf.hierarchical_conf import HierarchicalConf

from bietlejuice import BIETLEJUICE_PROJECT_ROOT
from bietlejuice.base.paths import QUERIES_DATALAKE_PATH, DATA_QUALITY_TESTS_PATH
from dags import DAG_PACKAGES_ROOT


class DuplicateDAGException(Exception):
    # TODO move to base/airflow/exceptions when imports conflicts are resolved
    """Raises when a DAG is duplicated inside the repository"""


class DAGPackagesPathService:
    """
    Abstracts and centralizes path/directory manipulations related to the DAGs or its inner contents.

    The methods are annotated, so we know if they can be used in Databricks or Composer to avoid errors
     and after migration we can easily uncouple the code between Orchestration and Jobs Core code.
    """

    @staticmethod
    def _get_dag_package_path(dag_name):
        """
        Returns the DAG's path (considering it is inside the DAG Packages structure)
        The path returned does not contain trailing slash like `/dags/bla/foo`

        * Method can be used Composer (GCS) or Databricks (wheel) *

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

        * Method can be used Composer (GCS) or Databricks (wheel) *

        :param dag_name: the DAG name, that is expected to be unique in the entire platform
        :return: full legacy DAG path
        """

        dag_path = f"{BIETLEJUICE_PROJECT_ROOT}/dags/{dag_name}"
        return os.path.exists(dag_path)

    @staticmethod
    def _read_file_content_from_filesystem(file_path: str):
        """
        Open a file from the bietlejuice wheel (for Databricks) or GCS path (for Composer)

        * Method can be used Composer (GCS) or Databricks (wheel) *

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
    def _read_dag_package_file_from_s3(sql_file_relative_path: str):
        """
        Read the DAG Package's file stored in S3 based on the relative file path.

        * Method used only in Databricks *

        :return: file content.
        """
        global_confs = HierarchicalConf([BIETLEJUICE_PROJECT_ROOT])
        dags_packages_files_prefix = global_confs.get_config(
            "dags_packages_files_path_in_s3"
        )

        s3_client = boto3.client("s3")
        sql_file_key = path.join(dags_packages_files_prefix, sql_file_relative_path)
        data = s3_client.get_object(
            Bucket=global_confs.get_config("databricks_bucket"), Key=sql_file_key
        )
        query = data["Body"].read().decode("utf-8")

        return query

    @staticmethod
    def get_dag_path(dag_name: str) -> str:
        """
        Gets the DAG's full path

        The path returned does not contain trailing slash like `/dags/bla/foo`

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

        :param dag_name: the DAG name
        :param table_name: the name of the table that the file is related to
        :param layer: the layer that the file is related to.
        :param intermediate_path: off intermediate path structure used in some DAGs
        :return: query content (the SQL)
        """
        intermediate_path = intermediate_path if intermediate_path is not None else ""
        if DAGPackagesPathService._is_dag_in_legacy_structure(dag_name):
            # TODO: remove after DAG-Packages migration
            sql_file_path = path.join(
                QUERIES_DATALAKE_PATH,
                dag_name,
                layer,
                intermediate_path,
                f"{table_name}.sql",
            )
            query_content = DAGPackagesPathService._read_file_content_from_filesystem(
                sql_file_path
            )
        else:
            sql_file_relative_path = path.join(
                "queries", dag_name, layer, intermediate_path, f"{table_name}.sql"
            )
            query_content = DAGPackagesPathService._read_dag_package_file_from_s3(
                sql_file_relative_path=sql_file_relative_path
            )

        if not query_content:
            raise FileNotFoundError(
                f"Query file was not found or is empty, dag_name={dag_name}, sql_file_relative_path={sql_file_relative_path}"
            )

        return query_content

    @staticmethod
    def list_queries_files_in_composer(
        dag_name: str, layer: str, intermediate_path: str = ""
    ) -> list:
        """
        Lists all query files for a given DAG and layer.

        * Method used only in Composer *

        :param dag_name: The DAG we want to list the D.Q. files.
        :param layer: the layer that the file is related to.
        :param intermediate_path: off intermediate path structure used in some DAGs
        :return: list of queries files without file extension (only table names)
        """
        if DAGPackagesPathService._is_dag_in_legacy_structure(dag_name):
            sql_files_folder = path.join(
                QUERIES_DATALAKE_PATH, dag_name, layer, intermediate_path
            )
        else:
            sql_files_folder = path.join(
                DAGPackagesPathService.get_dag_path(dag_name),
                "queries",
                layer,
                intermediate_path,
            )

        filename_regex = re.compile(rf"([a-z0-9_-]+)\.sql")
        files = glob(f"{sql_files_folder}/*.sql")
        table_names = []
        for file_path in files:
            table_names.append(re.search(filename_regex, file_path).group(1))

        return table_names

    @staticmethod
    def get_data_quality_file_content_in_spark_jobs(
        dag_name: str, table_name: str, layer: str, intermediate_path: str
    ):
        """
        Opens the Data Quality file according to the place it is stored (if it is in
         legacy path or in the DAGs packages)

        * Method used only in Databricks *

        :param dag_name: the DAG name
        :param layer: the layer that the file is related to.
        :param table_name: the name of the table that the file is related to
        :param intermediate_path: off intermediate path structure used in some DAGs
        :return: the data quality content
        """
        if DAGPackagesPathService._is_dag_in_legacy_structure(dag_name):
            # TODO: remove after DAG-Packages migration
            data_quality_file_path = path.join(
                DATA_QUALITY_TESTS_PATH,
                dag_name,
                layer,
                intermediate_path,
                f"{table_name}.yml",
            )
            data_quality_content = DAGPackagesPathService._read_file_content_from_filesystem(
                data_quality_file_path
            )
        else:
            data_quality_file_path = path.join(
                "data_quality", dag_name, layer, intermediate_path, f"{table_name}.yml"
            )

            try:
                data_quality_content = DAGPackagesPathService._read_dag_package_file_from_s3(
                    sql_file_relative_path=data_quality_file_path
                )
            except Exception as e:
                if "NoSuchKey" in str(e):
                    data_quality_content = DAGPackagesPathService._read_dag_package_file_from_s3(
                        sql_file_relative_path=data_quality_file_path.replace(
                            "yml", "yaml"
                        )
                    )
                else:
                    raise e

        if not data_quality_content:
            raise FileNotFoundError(
                f"Data quality file was not found, dag_name={dag_name}, data_quality_file_path={data_quality_file_path}"
            )

        return data_quality_content

    @staticmethod
    def data_quality_tests_file_exists_in_composer(
        dag_name: str, layer: str, table_name: str, intermediate_path: str = ""
    ) -> bool:
        """
        Checks if a data quality tests file for a given table exists.

        * Method used only in Composer *

        :param dag_name: the DAG name
        :param layer: the layer that the file is related to.
        :param table_name: the name of the table that the file is related to
        :param intermediate_path: off intermediate path structure used in some DAGs
        :return: True if the file exists, False if no file is found
        """

        if DAGPackagesPathService._is_dag_in_legacy_structure(dag_name):
            data_quality_file_path = path.join(
                DATA_QUALITY_TESTS_PATH,
                dag_name,
                layer,
                intermediate_path,
                f"{table_name}.yml",
            )
        else:
            data_quality_file_path = path.join(
                DAGPackagesPathService.get_dag_path(dag_name),
                "data_quality",
                layer,
                intermediate_path,
                f"{table_name}.yml",
            )

        return isfile(data_quality_file_path)

    @staticmethod
    def list_data_quality_tests_files_in_composer(dag_name: str, layer: str) -> list:
        """
        Lists all data quality tests files for a given DAG.

        * Method used only in Composer *

        :param dag_name: The DAG we want to list the D.Q. files.
        :param layer: the layer that the file is related to.
        :return: list of D.Q. files found.
        """
        if DAGPackagesPathService._is_dag_in_legacy_structure(dag_name):
            data_quality_folder = f"{DATA_QUALITY_TESTS_PATH}/{dag_name}/{layer}"
        else:
            data_quality_folder = path.join(
                DAGPackagesPathService.get_dag_path(dag_name), "data_quality", layer
            )

        files = glob(f"{data_quality_folder}/**/*.yml", recursive=True)
        filename_regex = re.compile(rf".*/([a-z0-9_-]+)(?:\.yml|\.yaml)")

        table_names = []
        for file_path in files:
            table_names.append(re.search(filename_regex, file_path).group(1))

        return table_names
