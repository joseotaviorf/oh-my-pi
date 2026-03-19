import re
from glob import glob
from os import path, scandir
import boto3

from hierarchical_conf.hierarchical_conf import HierarchicalConf

from bietlejuice import BIETLEJUICE_PROJECT_ROOT
from dags import DAG_PACKAGES_ROOT


class DAGPackagesPathService:
    """
    Abstracts and centralizes path/directory manipulations related to the DAGs or its inner contents.

    The methods are annotated, so we know if they can be used in Databricks or Composer to avoid errors
     and after migration we can easily uncouple the code between Orchestration and Jobs Core code.
    """

    __EXTENSIONS = {
        "dag_declaration": ["yml", "yaml"],
        "data_quality": ["yml", "yaml"],
        "metadata": ["yml", "yaml"],
        "configuration_file": ["yml", "yaml"],
        "doc_md": ["md"],
        "query": ["sql"],
    }

    __FILE_SUFFIXES = {"dag_declaration": "_declaration", "configuration_file": "_conf"}

    __FILE_NAME_TEMPLATES = {
        "dag_declaration": "{dag_name}{file_suffix}",
        "data_quality": "{table_name}",
        "metadata": "{table_name}",
        "configuration_file": "{dag_name}{file_suffix}",
        "doc_md": "{dag_name}",
        "query": "{table_name}",
    }

    __FILE_FOLDERS = {
        "data_quality": "data_quality",
        "metadata": "metadata",
        "query": "queries",
    }

    @staticmethod
    def _find_dag_in_line_folders(dag_name):
        """
        Finds DAG folder by traversing between all lines folders.

        :param dag_name: DAG name.
        :return: DAG folder path.
        """
        dag_packages_parent_folders = scandir(DAG_PACKAGES_ROOT)
        for line_folder in dag_packages_parent_folders:
            dag_path = path.join(line_folder.path, dag_name)
            if path.isdir(dag_path):
                return dag_path

        # non-existent DAG
        return None

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
    def _copy_file_from_s3_pyspark(bucket: str, sql_file_key: str):
        """
        Open a file from the s3

        * Method used only in Spark *
        * Not available with Databricks Shared Cluster *

        :param bucket: s3 bucket name
        :param sql_file_key: relative file path
        :return: file content
        """

        from pyspark import SparkFiles
        from bietlejuice.base.spark import sc

        sc.addFile(f"s3a://{bucket}/{sql_file_key}")
        with open(
            SparkFiles.get(sql_file_key.split("/")[-1]), mode="r", encoding="utf-8"
        ) as s3_file:
            return s3_file.read()

    @staticmethod
    def _copy_file_from_s3_databricks_volume(volume: str, sql_file_key: str):
        """
        Open a file from the databricks volume

        * Method used only in Databricks *

        :param volume: databricks volume path
        :param sql_file_key: relative file path
        :return: file content
        """

        with open(f"{volume}/{sql_file_key}", "r", encoding="utf-8") as f:
            query = f.read()
        return query

    @staticmethod
    def _read_file_from_s3_boto3(bucket: str, sql_file_key: str):
        """
        Read a file from the s3
        """
        s3 = boto3.resource("s3")
        return s3.Object(bucket, sql_file_key).get()["Body"].read().decode("utf-8")

    @staticmethod
    def _read_dag_package_file_from_s3(
        sql_file_relative_path: str, engine: str = "databricks_volume"
    ):
        """
        Read the DAG Package's file stored in S3 based on the relative file path.

        * Method used only in Databricks *

        :param sql_file_relative_path: relative file path
        :param engine: engine to read the file from. Options: "spark", "boto3" or "databricks_volume"

        :return: file content.
        """

        global_confs = HierarchicalConf([BIETLEJUICE_PROJECT_ROOT])
        dags_packages_files_prefix = global_confs.get_config(
            "dags_packages_files_path_in_s3"
        )
        sql_file_key = path.join(dags_packages_files_prefix, sql_file_relative_path)
        bucket = global_confs.get_config("databricks_bucket")
        volume = global_confs.get_config("volume_databricks_bucket")

        if engine == "spark":
            return DAGPackagesPathService._copy_file_from_s3_pyspark(
                bucket, sql_file_key
            )
        if engine == "databricks_volume":
            return DAGPackagesPathService._copy_file_from_s3_databricks_volume(
                volume, sql_file_key
            )
        if engine == "boto3":
            return DAGPackagesPathService._read_file_from_s3_boto3(bucket, sql_file_key)
        raise ValueError(f"Invalid s3 reader engine: {engine}")

    @staticmethod
    def _transform_into_intermediate_path(dag_name: str) -> str:
        """
        Transform complete DAG name into intermediate path, which is
        a structure that follows DAG Package folder structure.

        :param dag_name: DAG name.
        e.g.:
            dw_spark_datamarts.cross

        :return intermediate_path: DAG name turned into folder path structure.
        e.g.:
            dw_spark_datamarts/cross
        """
        intermediate_path = dag_name.replace(".", "/")
        return intermediate_path

    @staticmethod
    def get_dag_path(dag_name: str) -> str:
        """
        Gets the DAG's full path

        The path returned does not contain trailing slash, like `/dags/bla/foo`

        * Method used only in Composer *

        Finds the DAG path according to its location: inside the DAG Packages or in the legacy path (bietlejuice)
        :return: full DAG's parent path
        """
        if not dag_name:
            return None

        # Cases that the DAG has separated lines inside of it (Ex: dw_datamarts_spark.cross)
        intermediate_path = DAGPackagesPathService._transform_into_intermediate_path(
            dag_name=dag_name
        )

        dag_path = DAGPackagesPathService._find_dag_in_line_folders(intermediate_path)
        if dag_path:
            return dag_path

        # non-existent DAG
        return None

    @staticmethod
    def get_dag_parent_path(dag_name: str) -> str:
        """
        Gets the DAG's parent path

        * Method used only in Composer *

        Finds the DAG path according to its location: inside the DAG Packages or in the legacy path (bietlejuice)
        :return: full DAG's parent path
        """
        dag_path = DAGPackagesPathService.get_dag_path(dag_name)
        if dag_path:
            return path.dirname(dag_path)

        return None

    @staticmethod
    def get_query_file_content_in_spark_jobs(
        dag_name: str,
        table_name: str,
        layer: str = "",
        intermediate_path: str = "",
        engine: str = "databricks_volume",
    ):
        """
        Opens the SQL file according to the place it is stored (if it is in
         legacy path or in the DAGs packages)

        * Method used only in Databricks *

        :param dag_name: the DAG name
        :param table_name: the name of the table that the file is related to
        :param layer: the layer that the file is related to.
        :param intermediate_path: off intermediate path structure used in some DAGs
        :param engine: engine to read the file from. Options: "spark", "boto3" or "databricks_volume"
        :return: query content (the SQL)
        """
        intermediate_path = intermediate_path if intermediate_path is not None else ""
        sql_file_relative_path = path.join(
            "queries", dag_name, layer, intermediate_path, f"{table_name}.sql"
        )
        query_content = DAGPackagesPathService._read_dag_package_file_from_s3(
            sql_file_relative_path=sql_file_relative_path, engine=engine
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
        sql_files_folder = path.join(
            DAGPackagesPathService.get_dag_path(dag_name),
            "queries",
            layer,
            intermediate_path,
        )

        filename_regex = re.compile(r"([a-z0-9_-]+)\.sql")
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
        data_quality_file_path = path.join(
            "data_quality", dag_name, layer, intermediate_path, f"{table_name}.yml"
        )

        try:
            data_quality_content = (
                DAGPackagesPathService._read_dag_package_file_from_s3(
                    sql_file_relative_path=data_quality_file_path
                )
            )
        except Exception as e:
            if "NoSuchKey" in str(e):
                data_quality_content = (
                    DAGPackagesPathService._read_dag_package_file_from_s3(
                        sql_file_relative_path=data_quality_file_path.replace(
                            "yml", "yaml"
                        )
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
        data_quality_file_path = path.join(
            DAGPackagesPathService.get_dag_path(dag_name),
            "data_quality",
            layer,
            intermediate_path,
            f"{table_name}.yml",
        )

        return path.isfile(data_quality_file_path)

    @staticmethod
    def list_data_quality_tests_files_in_composer(dag_name: str, layer: str) -> list:
        """
        Lists all data quality tests files for a given DAG.

        * Method used only in Composer *

        :param dag_name: The DAG we want to list the D.Q. files.
        :param layer: the layer that the file is related to.
        :return: list of D.Q. files found.
        """
        data_quality_folder = path.join(
            DAGPackagesPathService.get_dag_path(dag_name), "data_quality", layer
        )

        files = glob(f"{data_quality_folder}/**/*.yml", recursive=True)
        filename_regex = re.compile(r".*/([a-z0-9_-]+)(?:\.yml|\.yaml)")

        table_names = []
        for file_path in files:
            table_names.append(re.search(filename_regex, file_path).group(1))

        return table_names

    @classmethod
    def artifact_file_exists(
        cls, artifact_type: str, dag_name: str, layer: str = "", table_name: str = ""
    ) -> bool:
        """
        Validates if a provided artifact exists in a provided DAG package.

        :param artifact_type: type of artifact being validated.
        :param dag_name: DAG which folder the artifact will be searched.
            Also used into naming templates.
        :param layer: datalake layer related to the artifact being searched.
            Optional. Defaults to "" (empty string).
        :param table_name: used to search for artifacts that contain the table name in their names.
            Optional. Defaults to "" (empty string).
        :return: boolean
        """
        extensions = cls.__EXTENSIONS[artifact_type]
        extensions_validation = []

        for ext in extensions:
            file_path = cls.generate_artifact_file_path(
                artifact_type, dag_name, layer, table_name, add_default_ext=False
            )
            file_path_ext = "{}.{}".format(file_path, ext)
            extensions_validation.append(path.isfile(file_path_ext))

        return any(extensions_validation)

    @classmethod
    def generate_artifact_file_name(
        cls,
        artifact_type: str,
        dag_name: str = "",
        table_name: str = "",
        add_default_ext: bool = True,
    ) -> str:
        """
        Generates the file name for a provided artifact of a provided DAG package.
        Follows the naming templates declared internally in the class constants.

        :param artifact_type: type of artifact for which the file name will be generated.
        :param dag_name: used to compose artifact names that contain the DAG name
            in their names. Optional. Defaults to "" (empty string).
        :param table_name: used to compose artifact names that contain the table name
            in their names. Optional. Defaults to "" (empty string).
        :param add_default_ext: switches whether to add or not the file extension into
            the end of the name. Optional. Defaults to `True`.
        :return: string
        """
        file_suffix = cls.__FILE_SUFFIXES.get(artifact_type, "")
        file_name = cls.__FILE_NAME_TEMPLATES[artifact_type].format(
            dag_name=dag_name, table_name=table_name, file_suffix=file_suffix
        )
        if add_default_ext:
            file_name = "{}.{}".format(file_name, cls.__EXTENSIONS[artifact_type][0])
        return file_name

    @classmethod
    def generate_artifact_file_path(
        cls,
        artifact_type: str,
        dag_name: str = "",
        layer: str = "",
        table_name: str = "",
        add_default_ext: bool = True,
    ) -> str:
        """
        Generates the file path for a provided artifact of a provided DAG package. Follows the
        naming templates declared internally in the class constants.

        :param artifact_type: type of artifact for which the file path will be generated.
        :param dag_name: used to compose the file path and into artifact names that contain
            the DAG name in their names. Optional. Defaults to "" (empty string).
        :param layer: datalake layer related to the artifact being provided.
            Optional. Defaults to "" (empty string).
        :param table_name: used to compose artifact names that contain the table name
            in their names. Optional. Defaults to "" (empty string).
        :param add_default_ext: switches whether to add or not the file extension into
            the end of the path. Optional. Defaults to `True`.
        :return: string
        """
        dag_path = cls.get_dag_path(dag_name=dag_name)

        if not dag_path:
            dag_path = path.join(DAG_PACKAGES_ROOT, dag_name)

        file_folder = cls.__FILE_FOLDERS.get(artifact_type, "")
        file_name = cls.generate_artifact_file_name(
            artifact_type, dag_name, table_name, add_default_ext
        )
        file_path = path.join(dag_path, file_folder, layer, file_name)

        return file_path

    @classmethod
    def list_artifact_file_paths(
        cls, artifact_type: str, dag_name: str, layer: str
    ) -> list:
        """
        Lists all artifact files for a given DAG.

        :param artifact_type: type of artifact being validated.
        :param dag_name: The DAG we want to list the D.Q. files.
        :param layer: the layer that the file is related to.
        :return: list of D.Q. files found.
        """

        glob_path = cls.generate_artifact_file_path(
            artifact_type, dag_name, layer, table_name="**", add_default_ext=False
        )
        file_paths = glob(pathname=glob_path, recursive=True)
        file_paths_with_correct_extension = [
            file_path
            for file_path in file_paths
            if file_path.endswith(tuple(cls.__EXTENSIONS[artifact_type]))
        ]

        return file_paths_with_correct_extension
