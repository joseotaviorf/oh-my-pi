import glob
from os import listdir
from os.path import isdir, isfile

import yaml
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH

logger = QuintoAndarLogger("FileService")


class FileService:
    @staticmethod
    @logger
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
    def list_layer_sql_files(source, layer, schema=None):
        """
        Return the SQL files for a given layer and schema (if specified)

        :param source: the source's directory name on db directory. E.g:
         autodialer, godfather, oscar.
        :param layer: the data lake layer
        :param schema: Source schema name
        :return: Tables SQL files list
        """
        raw_to_clean_path = f"{QUERIES_DATALAKE_PATH}{source}/{layer}"
        if schema:
            raw_to_clean_path = f"{raw_to_clean_path}/{schema}"

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
    def list_sql_files_without_extension_from_layer(source, layer, schema=None):
        """
        Return the SQL files without extension for a given layer and schema (if specified)

        :param source: the database base name for the table
        :param layer: the data lake layer
        :param schema: Source schema name
        :return: Tables SQL files list without extension
        """
        files = []
        for file in FileService.list_layer_sql_files(source, layer, schema):
            files.append(FileService.remove_file_extension(file))
        return files

    @staticmethod
    @logger
    def layer_table_sql_file_exists(source, layer, file_name, schema=None):
        """
        Checks for existence of enrichment query file for given source and schema

        :return: boolean
        """
        layer_queries_path = f"{QUERIES_DATALAKE_PATH}{source}/{layer}"
        if schema:
            layer_queries_path = f"{layer_queries_path}/{schema}"

        return isfile(f"{layer_queries_path}/{file_name}.sql")

    @staticmethod
    @logger
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
