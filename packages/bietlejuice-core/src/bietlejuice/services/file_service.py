import glob
import gzip
from io import BytesIO
from os import listdir
from os.path import isdir, isfile
from typing import List, Tuple

import yaml
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.paths import DAG_PACKAGES_ROOT, QUERIES_DATALAKE_PATH

logger = QuintoAndarLogger("FileService")


class FileService:
    @staticmethod
    def get_query_from_file_name(file_name: str):
        """
        Open a file from the bietlejuice wheel

        :param file_name: absolute file path
        :return: file content
        :raises: RuntimeError
        """
        try:
            with open(file_name) as f:
                return f.read()
        except OSError as ex:
            raise RuntimeError(
                f"m=get_query_from_file_name, file_name={file_name}, msg=file not found, ex={ex}"
            )

    @staticmethod
    def get_dict_from_yaml_file(file_path):
        """
        Given a file path, opens the file and returns the dictionary contained
         in this file.

        :param file_path: the full file path
        :rtype: dict
        """
        try:
            with open(file_path) as stream:
                try:
                    response = yaml.safe_load(stream)
                except yaml.YAMLError as ex:
                    logger.error(
                        f"m=get_dict_from_yaml_file, file_path={file_path}, msg=YAML content "
                        f"cannot be parsed, e={ex}"
                    )
                    raise ex
        except FileNotFoundError as ex:
            logger.error(
                f"m=get_dict_from_yaml_file, file_path={file_path}, msg=File not found in "
                "the specified path"
            )
            raise ex

        return response or {}

    @staticmethod
    def list_files(path):
        """
        Return the files that are inside the path
        :param path: files path
        :return: files list
        """
        if not isdir(path):
            raise RuntimeError(
                f"m=list_files path={path}, msg=Given path does not exist"
            )
        return [file for file in listdir(path) if isfile(f"{path}/{file}")]

    @staticmethod
    def list_all_files_recursively(root_directory, extension="*"):
        """
        Recursively lists all the files inside the path and its subdirectories.
        If specified an extension, only files from this extension will be listed.

        :param root_directory: The root path to be searched (without trailing slash)
        :type root_directory: str
        :param extension: Files extension filter
        :type extension: str
        :return: list of files found
        :rtype: generator object
        """
        files = glob.iglob(f"{root_directory}/**/*.{extension}", recursive=True)
        return files

    @staticmethod
    def layer_table_sql_file_exists(source, layer, file_name, tree_path=None):
        """
        Checks for existence of enrichment query file for given source and tree_path

        :return: boolean
        """
        layer_queries_path = f"{QUERIES_DATALAKE_PATH}{source}/{layer}"
        if tree_path:
            layer_queries_path = f"{layer_queries_path}/{tree_path}"

        return isfile(f"{layer_queries_path}/{file_name}.sql")

    @staticmethod
    def table_dim_query_exists(source, schema, table_name):
        """
        Checks for existence of query file for given source and schema

        :param source
        :param schema: Source schema name
        :param table_name
        :return: boolean
        """
        clean_to_staging_path = f"{QUERIES_DATALAKE_PATH}{source}/staging"
        return isfile(f"{clean_to_staging_path}/{schema}/dim_{table_name}.sql")

    @staticmethod
    def remove_file_extension(file_name):
        ext_pos = file_name.rfind(".")
        return file_name[:ext_pos]

    @staticmethod
    def get_table_info_from_path(path: str) -> Tuple[str, str, str, str, str, str]:
        """
        Given a query/metadata table file path, get informations about that table
        The informations are:
        :param path: path to a SQL or metadata file
            e.g. classified_leads/clean/lead_reply.sql or classified_leads/clean/lead_reply.yaml
        :returns: source, layer, context, dag, ingestion_type, table
        :rtype: Tuple[str, str, str, str, str, str]
        """
        path_tree = path.split(".")[0].split("/")
        if len(path_tree) < 4:
            raise ValueError(
                f"m=get_table_info_from_path, path={path},"
                f" msg=Cannot infer table info from path: not enough levels"
            )
        if len(path_tree) > 6:
            raise ValueError(
                f"m=get_table_info_from_path, path={path},"
                f" msg=Cannot infer table info from path: too many levels"
            )

        source = path_tree[0]
        layer = path_tree[2]

        # default values
        ingestion_type = "full"
        dag = source
        context = source
        table = path_tree[-1]

        if len(path_tree) == 5:
            if path_tree[3] in {"incremental", "full"}:
                ingestion_type = path_tree[3]
            else:
                context = path_tree[3]
                # Hard coded while the Gsheets Guild is still creating the new gsheets DAG Builder,
                # which will have the correct path structure
                if "gsheets" in source:
                    dag = f"gsheets.{context}"
                else:
                    dag = f"{source}.{context}"
        if len(path_tree) == 6:
            context = path_tree[3]
            origin = path_tree[4]
            dag = f"{context}.{origin}"

        return source, layer, context, f"bietlejuice.{dag}", ingestion_type, table

    @staticmethod
    def list_dag_files() -> List[str]:
        """
        List all composer dag file paths.

        :return: a list of dag file paths
            e.g.
            - '/Users/my-user/bi-etl-ejuice/bietlejuice/dags/source/dag_file.py'
            - '/Users/my-user/bi-etl-ejuice/bietlejuice/dags/source/context/dag_file.py'
        :rtype: List[str]
        """
        all_dag_packages_files = glob.glob(
            f"{DAG_PACKAGES_ROOT}/**/*.py", recursive=True
        )

        filtered_files = []
        for file in all_dag_packages_files:
            if "spark_jobs" in file or "__init__.py" in file:
                continue
            filtered_files.append(file)
        return filtered_files

    @staticmethod
    def get_data_from_zip_file(zip_file) -> List[str]:
        data = []
        for name in zip_file.namelist():
            with gzip.open(BytesIO(zip_file.read(name)), "rb") as gzip_file:
                data.extend(gzip_file.read().decode("utf-8").splitlines())
        return data
