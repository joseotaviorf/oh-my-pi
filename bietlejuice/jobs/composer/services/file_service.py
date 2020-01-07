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
    @logger
    def get_dict_from_yaml_file(file_path):
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
    @logger
    def list_raw_to_clean_sql_files(source, schema):
        """
        Return the SQL files used to move table from raw to clean for given schema

        :param schema: Source schema name
        :return: Tables SQL files list
        """
        raw_to_clean_path = f"{QUERIES_DATALAKE_PATH}{source}/clean"
        schema_path = f"{raw_to_clean_path}/{schema}"
        if not isdir(schema_path):
            raise RuntimeError(
                f"m=list_raw_to_clean_sql_files path={raw_to_clean_path}, "
                f"schema={schema}, msg=Given schema does not have a dir"
            )

        return listdir(schema_path)

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
