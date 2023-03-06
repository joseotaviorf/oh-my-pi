import re
from pathlib import Path
from typing import List, Dict, Any

import yaml
from yamale import yamale

from bietlejuice.services import FileService
from scripts.services.metadata_file_info import MetadataFileInfo
from dags import DAG_PACKAGES_ROOT


class MetadataFileService:
    """
    Class used to validate and extract information from metadata files
    """

    DAGS_METADATA_PATHS_REGEX = re.compile(
        rf"(?:.*/)?dags/(?P<domain>\w+)/(?P<dag>\w+)/metadata/(?P<layer>\w+)(?:/\w+)?/(?P<table_name>\w+)\.(?:yml|yaml)"
    )

    def __init__(self):
        base_path = f"{Path(__file__).parent}/metadata_file_schemas"
        self.file_schema = yamale.make_schema(f"{base_path}/metadata_file_schema.yml")
        self.raw_file_schema = yamale.make_schema(
            f"{base_path}/raw_metadata_file_schema.yml"
        )

    @staticmethod
    def filter_metadata_files(files) -> List[str]:
        """
        Given a list of files, returns a list consisting only of metadata files
        :param files: list of files to be filtered
        :type files: List[str]
        :return: list of filtered files
        :rtype: List[str]
        """
        return list(
            filter(
                lambda file: re.match(
                    MetadataFileService.DAGS_METADATA_PATHS_REGEX, file
                ),
                files,
            )
        )

    @staticmethod
    def list_metadata_files() -> List[str]:
        """
        Scans DAG_PACKAGES_ROOT and returns all metadata files
        :return: list of paths to metadata files
        :rtype: List[str]
        """
        return MetadataFileService.filter_metadata_files(
            list(FileService.list_all_files_recursively(DAG_PACKAGES_ROOT, "yml"))
        )

    @staticmethod
    def _get_info_from_path(path: str) -> Dict[str, str]:
        """
        Extracts information from metadata file path
        :param path: Path to a metadata file
        :type path: str
        :return: dict with domain, dag, layer and table_name
        :rtype: dict
        """
        return re.match(MetadataFileService.DAGS_METADATA_PATHS_REGEX, path).groupdict()

    @staticmethod
    def _get_info_from_content(content: Dict[str, Any], layer: str) -> MetadataFileInfo:
        """
        given the content of a metadata file and it's layer, returns a MetadataFileInfo object
        :param content: Dict with content of a metadata file
        :type content: Dict[str, Any]
        :param layer: Layer of the metadata file. Raw, clean, etc
        :type layer: str
        :return: a MetadataFileInfo with information about the file
        :rtype: MetadataFileInfo
        """
        database_name = content["database_name"]
        table_name = content["table_name"]
        s3_path = f"metadata/{database_name}/{table_name}.yml"
        has_lineage = False
        has_documentation = False
        has_tags = False

        if content.get("columns"):
            for column_name, column_data in content["columns"].items():
                try:
                    keys = column_data.keys()
                except AttributeError as err:
                    print(
                        f"m=_get_info_from_content, db={database_name}, table={table_name}, column={column_name}, msg=Column is not a map, this file content might not be correctly validated"
                    )
                    continue
                if "lineage" in keys:
                    has_lineage = True
                if "tags" in keys:
                    has_tags = True
                if "description" in keys:
                    has_documentation = True
        else:
            if layer == "raw":
                has_tags = True

        return MetadataFileInfo(
            database_name=database_name,
            table_name=table_name,
            s3_path=s3_path,
            has_lineage=has_lineage,
            has_tags=has_tags,
            has_documentation=has_documentation,
            layer=layer,
        )

    @staticmethod
    def get_info(path: str) -> MetadataFileInfo:
        """
        Reads metadata file and extracts information from its content
        :param path: Path to a metadata file
        :type path: str
        :return: dict with database name, table name, s3 path, if the file has documentation, lineage and tags
        :rtype:
        """
        path_info = MetadataFileService._get_info_from_path(path)
        domain = path_info["domain"]
        dag = path_info["dag"]
        layer = path_info["layer"]

        with open(path, "r") as fp:
            content = yaml.safe_load(fp)

        file_info = MetadataFileService._get_info_from_content(content, layer)
        file_info.domain = domain
        file_info.dag = dag
        file_info.layer = layer
        file_info.local_path = path

        return file_info

    def validate_file(self, file_path: str) -> List[Any]:
        """
        Given the path to a metadata file, validates if it conforms to the metadata files schemas
        :param file_path: path to a metadata file
        :type file_path: str
        :return: List of validations results from Yamale
        :rtype: List[Any]
        """
        yaml_data = yamale.make_data(file_path)
        yaml_content, _ = yaml_data[0]
        table_info = MetadataFileService._get_info_from_path(file_path)

        if table_info["layer"] == "raw":
            return yamale.validate(self.raw_file_schema, yaml_data)
        else:
            return yamale.validate(self.file_schema, yaml_data)
