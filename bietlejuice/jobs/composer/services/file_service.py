import glob
from os import listdir
from os.path import isdir, isfile
import re
from typing import Generator, Tuple, List

import yaml
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.paths import (
    QUERIES_DATALAKE_PATH,
    DATALAKE_METADATA_PATH,
    DATA_QUALITY_TESTS_PATH,
)
from bietlejuice.jobs.composer.dags import COMPOSER_DAGS_PATH

logger = QuintoAndarLogger("FileService")


class FileService:
    @staticmethod
    def get_query_from_file_name(file_name):
        try:
            with open(file_name) as f:
                return f.read()
        except IOError as ex:
            raise RuntimeError(
                "m=get_query_from_file_name, file_name={}, msg=file not found, ex={}".format(
                    file_name, ex
                )
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
            with open(file_path, "r") as stream:
                try:
                    response = yaml.safe_load(stream)
                except yaml.YAMLError as ex:
                    logger.error(
                        "m=get_dict_from_yaml_file, file_path={}, msg=YAML content "
                        "cannot be parsed, e={}".format(file_path, ex)
                    )
                    raise ex
        except FileNotFoundError as ex:
            logger.error(
                "m=get_dict_from_yaml_file, file_path={}, msg=File not found in "
                "the specified path".format(file_path)
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

        return listdir(path)

    @staticmethod
    def list_layer_sql_files(source, layer, tree_path=None):
        """
        Return the SQL files for a given layer and tree_path (if specified)

        :param source: the source's directory name on db directory. E.g:
         autodialer, godfather, oscar.
        :param layer: the data lake layer
        :param tree_path: The rest of the path, used for full or incremental ingestions or specific contextual ingestions e:g crawlers listings
        :return: Tables SQL files list
        """
        raw_to_clean_path = f"{QUERIES_DATALAKE_PATH}{source}/{layer}"
        if tree_path:
            raw_to_clean_path = f"{raw_to_clean_path}/{tree_path}"

        return FileService.list_files(raw_to_clean_path)

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
    def list_sql_files_without_extension_from_layer(source, layer, tree_path=None):
        """
        Return the SQL files without extension for a given layer and tree_path (if specified)

        :param source: the database base name for the table
        :param layer: the data lake layer
        :param tree_path: The rest of the path, used for full or incremental ingestions or specific contextual ingestions e:g crawlers listings
        :return: Tables SQL files list without extension
        """
        files = []
        for file in FileService.list_layer_sql_files(source, layer, tree_path):
            files.append(FileService.remove_file_extension(file))
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
    def metadata_file_exists(
        relative_file_path: str, layer: str, table_name, check_all_tables=False
    ) -> bool:
        """
        Checks if a metadata file for a given table exists. If check_all_tables is True,
        checks if at least the folder for the relative_file_path and layer exists.
        :param relative_file_path: The relative path to the file.
            This should be the same as the relative_query_path used in other tasks
            e.g:
            `dw_smart_price`, `dw_marketing_costs/google`, etc
        :param layer: The layer that the file is related to.
        :param table_name: The name of the table that the file is related to
        :param check_all_tables: if all tables are being checked or not
        :return: True if the file exists, False if no file is found
        """
        if check_all_tables:
            folder = glob.glob(f"{DATALAKE_METADATA_PATH}/{relative_file_path}/{layer}")
            if folder:
                return True
            return False
        else:
            for extension in ("yml", "yaml"):
                files = glob.glob(
                    f"{DATALAKE_METADATA_PATH}/{relative_file_path}/{layer}/**/{table_name}.{extension}",
                    recursive=True,
                )
                if files and files[0]:
                    return True
            return False

    @staticmethod
    def list_metadata_files() -> Generator[str, None, None]:
        """
        Yields all metadata YAML file paths.
        :return: A generator that yields metadata file paths
        """
        for extension in ("*.yml", "*.yaml"):
            for file in glob.iglob(
                f"{DATALAKE_METADATA_PATH}/**/{extension}", recursive=True
            ):
                yield file

    @staticmethod
    def data_quality_tests_file_exists(
        relative_file_path: str, layer: str, table_name
    ) -> bool:
        """
        Checks if a data quality tests file for a given table exists.
        :param relative_file_path: the relative path to the file.
            This should be the same as the relative_query_path used in other tasks
            e.g:
            `dw_smart_price`, `dw_marketing_costs/google`, etc
        :param layer: the layer that the file is related to.
        :param table_name: the name of the table that the file is related to
        :return: True if the file exists, False if no file is found
        """
        for extension in ("yml", "yaml"):
            files = glob.glob(
                f"{DATA_QUALITY_TESTS_PATH}/{relative_file_path}/{layer}/**/{table_name}."
                f"{extension}",
                recursive=True,
            )
            if files and files[0]:
                return True
        return False

    @staticmethod
    def list_data_quality_tests_files(relative_file_path: str, layer: str) -> list:
        """
        Lists all data quality tests files for a given relative file path.
        :param relative_file_path: The relative path to lists files to.
        :param layer: the layer that the file is related to.
        :return: the list of files for the given relative file path.
        """
        filename_regex = re.compile(
            rf".*/{relative_file_path}/{layer}/([a-z0-9_-]+)(?:\.yml|\.yaml)"
        )
        table_names = []
        for extension in ("*.yml", "*.yaml"):
            files = glob.glob(
                f"{DATA_QUALITY_TESTS_PATH}/{relative_file_path}/{layer}/**/{extension}",
                recursive=True,
            )
            if files:
                for file_path in files:
                    table_names.append(re.search(filename_regex, file_path).group(1))

        return table_names

    @staticmethod
    def get_data_quality_test_file(relative_file_path: str, layer: str, table_name: str) -> str:
        file_search_path = f"{DATA_QUALITY_TESTS_PATH}/{relative_file_path}/{layer}/**/{table_name}.y*ml"
        files = glob.glob(file_search_path, recursive=True)

        if files and files[0]:
            return files[0]

        error_msg = (
            f"m=get_data_quality_test_file, file_search_path={file_search_path}, "
            f"msg=The validation file for this table could not be reached. "
            f"Check if it is in the right folder and has the same name as the table. "
            f"Expeted location: (composer/base/db/datalake/data_quality/{{context}}/{{layer}}/)"
        )
        raise FileNotFoundError(error_msg)

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
        source = path_tree[0]
        layer = path_tree[1]

        # default values
        ingestion_type = "full"
        dag = source
        context = source
        table = None

        if len(path_tree) < 3:
            raise ValueError(
                f"m=get_table_info_from_path, path={path},"
                f" msg=Cannot infer table info from path: not enough levels"
            )
        elif len(path_tree) > 6:
            raise ValueError(
                f"m=get_table_info_from_path, path={path},"
                f" msg=Cannot infer table info from path: too many levels"
            )
        elif len(path_tree) == 3:
            table = path_tree[2]
        elif len(path_tree) == 4:
            if path_tree[2] in {"full", "incremental"}:
                ingestion_type = path_tree[2]
            else:
                context = path_tree[2]
            table = path_tree[3]
        elif len(path_tree) == 5:
            context = path_tree[2]
            if path_tree[3] in {"full", "incremental"}:
                ingestion_type = path_tree[3]
            else:
                dag = path_tree[3]
            table = path_tree[4]
        elif len(path_tree) == 6:
            context = path_tree[2]
            dag = path_tree[3]
            ingestion_type = path_tree[4]
            table = path_tree[5]

        return source, layer, context, dag, ingestion_type, table

    @staticmethod
    def list_dag_files() -> List[str]:
        """
        List all composer dag file paths.
        :return: a list of dag file paths
            e.g.
            - '/Users/my-user/bi-etl-ejuice/bietlejuice/jobs/composer/dags/source/dag_file.py'
            - '/Users/my-user/bi-etl-ejuice/bietlejuice/jobs/composer/dags/source/context/dag_file.py'
        :rtype: List[str]
        """
        all_files = glob.glob(f"{COMPOSER_DAGS_PATH}/**/*.py", recursive=True)
        filtered_files = []
        for file in all_files:
            split = file.split("/")
            if "spark_jobs" in split or "__init__.py" in split:
                continue
            filtered_files.append(file)
        return filtered_files
