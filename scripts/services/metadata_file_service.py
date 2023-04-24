import os
import re
from pathlib import Path
from typing import List, Dict, Any, Tuple

import yaml
from yamale import yamale, YamaleError

from bietlejuice.services import FileService
from scripts.services.metadata_file_info import MetadataFileInfo
from dags import DAG_PACKAGES_ROOT


class ReverseMetadataFileException(Exception):
    def __init__(self, file, layer):
        self.data = file
        self.errors = [
            f"Error: Reverse layer do not need metadata files. Remove this file"
        ]
        super().__init__(
            f"file={file}, layer={layer}, msg=Reverse layer do not need metadata files. Remove this file"
        )


class MetadataFileService:
    """
    Class used to validate and extract information from metadata files
    """

    INFO_FROM_PATHS_REGEX = re.compile(
        r"(?:.*/)?dags/(?P<domain>\w+)/(?P<dag>\w+)/(?P<metadata_or_queries>metadata|queries)/(?P<layer>\w+)(?:/\w+)?/(?P<table_name>\w+)\.(?P<extension>\w{3,4})"
    )
    DAGS_SQL_PATHS_REGEX = re.compile(
        r"(?:.*/)?dags/(?P<domain>\w+)/(?P<dag>\w+)/queries/(?P<layer>\w+)(?:/\w+)?/(?P<table_name>\w+)\.(?:sql)"
    )
    DAGS_METADATA_PATHS_REGEX = re.compile(
        r"(?:.*/)?dags/(?P<domain>\w+)/(?P<dag>\w+)/metadata/(?P<layer>\w+)(?:/\w+)?/(?P<table_name>\w+)\.(?:yml|yaml)"
    )

    def __init__(self):
        base_path = f"{Path(__file__).parent}/metadata_file_schemas"
        self.schemas = {
            "raw": yamale.make_schema(f"{base_path}/raw_schema.yml"),
            "clean": yamale.make_schema(f"{base_path}/clean_schema.yml"),
            "enrich_dw": yamale.make_schema(f"{base_path}/enrich_dw_schema.yml"),
            "metric": yamale.make_schema(f"{base_path}/metric_schema.yml"),
        }

    @staticmethod
    def filter_metadata_files(files_and_status) -> List[Tuple[str, str]]:
        """
        Given a list of files_and_status tuples, returns a list consisting only of metadata files
        :param files: list of files to be filtered
        :type files: List[str]
        :return: list of filtered files
        :rtype: List[str]
        """
        filtered_files = []
        for file, status in files_and_status:
            if re.match(MetadataFileService.DAGS_METADATA_PATHS_REGEX, file):
                filtered_files.append((file, status))
        return filtered_files

    @staticmethod
    def filter_query_files(files_and_status) -> List[Tuple[str, str]]:
        """
        Given a list of files_and_status tuples, returns a list consisting only of metadata files
        :param files: list of files to be filtered
        :type files: List[str]
        :return: list of filtered files
        :rtype: List[str]
        """
        filtered_files = []
        for file, status in files_and_status:
            if re.match(MetadataFileService.DAGS_SQL_PATHS_REGEX, file):
                filtered_files.append((file, status))
        return filtered_files

    @staticmethod
    def list_metadata_files() -> List[Tuple[str, str]]:
        """
        Scans DAG_PACKAGES_ROOT and returns all metadata files
        :return: list of paths to metadata files
        :rtype: List[str]
        """
        return MetadataFileService.filter_metadata_files(
            [
                (file, "M")
                for file in FileService.list_all_files_recursively(
                    DAG_PACKAGES_ROOT, "yml"
                )
            ]
        )

    @staticmethod
    def list_query_files() -> List[Tuple[str, str]]:
        """
        Scans DAG_PACKAGES_ROOT and returns all metadata files
        :return: list of paths to metadata files
        :rtype: List[str]
        """
        return MetadataFileService.filter_metadata_files(
            [
                (file, "M")
                for file in FileService.list_all_files_recursively(
                    DAG_PACKAGES_ROOT, "sql"
                )
            ]
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
        return re.match(MetadataFileService.INFO_FROM_PATHS_REGEX, path).groupdict()

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
        has_metric = False

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
                if "metric" in keys:
                    has_metric = True
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
            has_metric=has_metric,
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

    def validate_file(self, file_path: str, status: str) -> List[Any]:
        """
        Given the path to a metadata file, validates if it conforms to the metadata files schemas
        :param file_path: path to a metadata file
        :type file_path: str
        :param status: Github file status.
        :type status: str
        :return: List of validations results from Yamale
        :rtype: List[Any]
        """
        yaml_data = yamale.make_data(file_path)
        yaml_content, _ = yaml_data[0]
        table_info = MetadataFileService._get_info_from_path(file_path)
        layer = table_info["layer"]

        if layer == "raw":
            return yamale.validate(self.schemas["raw"], yaml_data)
        elif layer == "clean":
            return yamale.validate(self.schemas["clean"], yaml_data)
        elif layer in ["enrich", "dw"]:
            return yamale.validate(self.schemas["enrich_dw"], yaml_data)
        elif layer == "metric":
            return yamale.validate(self.schemas["metric"], yaml_data)
        elif layer == "reverse":
            raise ReverseMetadataFileException(file_path, layer)

    def sql_file_has_equivalent_metadata_file(
        self, file_path: str, status: str
    ) -> bool:
        """
        Given the path to a bi-etl-ejuice sql file, checks if the file has a corresponding metadata file
        :param file_path: path to the sql file
        :type file_path: str
        :param status: the git status of the file. A for new file, M for modified file, D for deleted, etc
        :type status: str
        :return: true if the metadata file exists, otherwise false
        :rtype: false
        """
        table_info = MetadataFileService._get_info_from_path(file_path)
        layer = table_info.get("layer")

        if layer in {"raw", "clean", "enrich", "dw", "metric"}:
            return os.path.isfile(
                file_path.replace("/queries/", "/metadata/").replace("sql", "yml")
            ) or os.path.isfile(
                file_path.replace("/queries/", "/metadata/").replace("sql", "yaml")
            )
        else:
            if layer:
                print(
                    f"m=sql_file_has_equivalent_metadata_file, file_path={file_path}, layer={layer}, msg=This layer does not requires a metadata file"
                )
                return True
            else:
                print(
                    f"m=sql_file_has_equivalent_metadata_file, file_path={file_path}, msg=Could not infer layer, skipping file"
                )
                return True
