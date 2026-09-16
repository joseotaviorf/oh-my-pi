import os
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import yaml
from sqlglot import exp, parse_one
from yamale import yamale

from bietlejuice.base.db.datalake_metastore_mapping import (
    CONSUMPTION_SCHEMAS,
    apply_naming_convention,
)
from bietlejuice.services.file_service import FileService
from dags import DAG_PACKAGES_ROOT
from scripts.services.metadata_file_info import MetadataFileInfo

_DB_NAME_FORMULA = {
    "transactional": "datalake_{schema}_transactional",
    "raw": "datalake_{schema}_raw",
    "clean": "datalake_{schema}_clean",
    "clean_staging": "datalake_{schema}_clean_staging",
    "core": "{schema}",
    "enrich": "datalake_{schema}",
    "dw": "dw_{schema}",
    "dw_staging": "dw_{schema}_staging",
    "metric": "metric_{schema}",
    # Consumption is prefix-free: physical metastore DB name is the schema itself
    # (e.g. ops_finance.foo). No datalake_ / consumption_ layer prefix.
    "consumption": "{schema}",
    "transformation": "transformation_{schema}",
}

_DAG_DIR_FROM_METADATA_PATH = re.compile(r"((?:.*/)?dags/[^/]+/[^/]+)/metadata/")


class ReverseMetadataFileException(Exception):
    def __init__(self, file, layer):
        self.data = file
        self.errors = [
            "Error: Reverse layer do not need metadata files. Remove this file"
        ]
        super().__init__(
            f"file={file}, layer={layer}, msg=Reverse layer do not need metadata files. Remove this file"
        )


class MetricValidateLayerException(Exception):
    def __init__(self, file, table, layer):
        self.data = file
        self.errors = [
            f"Error: Metric layer does not allow datamarts or tables from raw and clean layers in sql file. Table={table}"
        ]

        super().__init__(
            f"file={file}, layer={layer}, msg=Metric layer does not allow datamarts or tables from raw and clean layers in sql file. Table={table}"
        )


class TableNameMismatchException(Exception):
    def __init__(self, file, file_table_name, yaml_table_name):
        self.data = file
        self.errors = [
            f"Error: table_name in YAML ('{yaml_table_name}') does not match the file name ('{file_table_name}'). "
            f"Rename the file to '{yaml_table_name}.yml' or update table_name to '{file_table_name}'."
        ]
        super().__init__(
            f"file={file}, file_table_name={file_table_name}, yaml_table_name={yaml_table_name}, "
            f"msg=table_name in YAML does not match the file name"
        )


class DatabaseNameMismatchException(Exception):
    def __init__(self, file, declared_db, expected_db, dag_name, layer, schema):
        self.data = file
        self.errors = [
            f"Error: database_name '{declared_db}' does not match the expected '{expected_db}' "
            f"(dag='{dag_name}', layer='{layer}', schema='{schema}'). "
            f"Update database_name to '{expected_db}'."
        ]
        super().__init__(
            f"file={file}, declared={declared_db}, expected={expected_db}, "
            f"dag={dag_name}, layer={layer}, schema={schema}"
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
        base_path = Path(__file__).parent / "metadata_file_schemas"
        self.schemas = {
            "raw": yamale.make_schema(str(base_path / "raw_schema.yml")),
            "clean": yamale.make_schema(str(base_path / "clean_schema.yml")),
            "core": yamale.make_schema(str(base_path / "core_schema.yml")),
            "enrich_dw": yamale.make_schema(str(base_path / "enrich_dw_schema.yml")),
            "metric": yamale.make_schema(str(base_path / "metric_schema.yml")),
        }

    @staticmethod
    def _load_declaration(file_path: str, dag_name: str) -> Optional[dict]:
        match = re.match(_DAG_DIR_FROM_METADATA_PATH, file_path)
        if not match:
            return None
        declaration_path = Path(match.group(1)) / f"{dag_name}_declaration.yml"
        if not declaration_path.exists():
            return None
        with open(declaration_path) as f:
            return yaml.safe_load(f)

    @staticmethod
    def _find_table_customization(table_name: str, tables_customization: dict) -> dict:
        table_custom = tables_customization.get(table_name, {})
        if isinstance(table_custom, dict) and table_custom:
            return table_custom
        for customization in tables_customization.values():
            if not isinstance(customization, dict):
                continue
            if customization.get("clean_table_name") == table_name:
                return customization
        return {}

    @staticmethod
    def _compute_schema(
        dag_name: str,
        layer: str,
        custom_schema: Optional[str],
        table_name: str,
        tables_customization: dict,
    ) -> str:
        # Per-table custom_schema takes precedence (used in DW layer)
        table_custom = MetadataFileService._find_table_customization(
            table_name, tables_customization
        )
        if "custom_schema" in table_custom:
            return table_custom["custom_schema"]
        # Metric schema is always derived from dag name; workflow ignores custom_schema
        if layer == "metric":
            business_unit = dag_name.split("__")[0]
            return business_unit.replace("metric_", "")
        # Workflow-level custom_schema
        if custom_schema:
            return custom_schema
        # Default fallback mirrors TableAttributes._get_schema
        return dag_name.replace("enrich_", "")

    @staticmethod
    def _validate_database_name(file_path: str, content: dict, table_info: dict):
        declared_db = content.get("database_name")
        if not declared_db:
            return
        dag_name = table_info["dag"]
        layer = table_info["layer"]
        table_name = table_info["table_name"]
        declaration = MetadataFileService._load_declaration(file_path, dag_name)
        if declaration is None:
            return
        workflow_args = declaration.get("workflow") or {}
        custom_schema = workflow_args.get("custom_schema")
        tables_customization = workflow_args.get("tables_customization") or {}
        schema = MetadataFileService._compute_schema(
            dag_name, layer, custom_schema, table_name, tables_customization
        )
        formula = _DB_NAME_FORMULA.get(layer)
        if formula is None:
            return
        expected_db = formula.format(schema=schema)
        # Consumption is prefix-free by formula (`{schema}`); do not route it through
        # apply_naming_convention (enrich-era datalake_ exception list).
        # Other layers still apply that convention so governed enrich schemas drop
        # the historical datalake_ prefix and match runtime metastore names.
        if layer != "consumption":
            expected_db = apply_naming_convention(schema, expected_db)
        if declared_db != expected_db:
            raise DatabaseNameMismatchException(
                file_path, declared_db, expected_db, dag_name, layer, schema
            )

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
                except AttributeError:
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

        with open(path) as fp:
            content = yaml.safe_load(fp)

        file_info = MetadataFileService._get_info_from_content(content, layer)
        file_info.domain = domain
        file_info.dag = dag
        file_info.layer = layer
        file_info.local_path = path

        return file_info

    def get_table_layer(self, schema: str):
        """
        Read the schema and return the table layer.

        :param schema: Schema name
        :type schema: str
        :rtype: str
        """

        if schema and schema.lower() in CONSUMPTION_SCHEMAS:
            return "consumption"
        if re.match(r"^transformation_.*", schema):
            return "transformation"
        if re.match(r".*_raw$", schema):
            return "raw"
        elif re.match(r".*_clean$", schema):
            return "clean"
        elif re.match(r"^core_.*", schema):
            return "core"
        elif re.match(r"^dw_datamarts_.*", schema):
            return "dw_datamarts"
        elif re.match(r"^dw_.*", schema):
            return "dw"
        elif re.match(r"^metric_.*", schema):
            return "metric"
        else:
            return "enrich"

    def validate_metric_file(self, file_path: str, yaml_data: Dict):
        """
        Given the metric metadata, validate if it use only tables in enrich and dw layer.

        :param file_path: Metric metadata file path.
        :type file_path: str
        :param yaml_data: Metric metadata.
        :type yaml_data: Dict
        :rtype: List[Any]
        """

        sql_file_path = (
            file_path.replace("metadata", "queries")
            .replace(".ymal", ".sql")
            .replace(".yml", ".sql")
        )
        with open(sql_file_path) as sql_file:
            tables = [table for table in parse_one(sql_file.read()).find_all(exp.Table)]

        for table in tables:
            if self.get_table_layer(table.db) in ["raw", "clean", "dw_datamarts"]:
                raise MetricValidateLayerException(
                    file_path,
                    f"{table.db}.{table.name}",
                    "metric",
                )

        return yamale.validate(self.schemas["metric"], yaml_data)

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
        table_info = MetadataFileService._get_info_from_path(file_path)
        layer = table_info["layer"]

        with open(file_path) as f:
            content = yaml.safe_load(f)
        yaml_table_name = content.get("table_name", "")
        file_table_name = table_info["table_name"]
        if yaml_table_name != file_table_name:
            raise TableNameMismatchException(
                file_path, file_table_name, yaml_table_name
            )

        MetadataFileService._validate_database_name(file_path, content, table_info)

        if layer == "raw":
            return yamale.validate(self.schemas["raw"], yaml_data)
        elif layer == "clean":
            return yamale.validate(self.schemas["clean"], yaml_data)
        elif layer == "core":
            return yamale.validate(self.schemas["core"], yaml_data)
        elif layer in ["enrich", "dw", "consumption", "transformation"]:
            return yamale.validate(self.schemas["enrich_dw"], yaml_data)
        elif layer == "metric":
            return self.validate_metric_file(file_path, yaml_data)
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

        if layer in {
            "raw",
            "clean",
            "core",
            "enrich",
            "dw",
            "metric",
            "consumption",
            "transformation",
        }:
            return os.path.isfile(
                file_path.replace("/queries/", "/metadata/").replace(".sql", ".yml")
            ) or os.path.isfile(
                file_path.replace("/queries/", "/metadata/").replace(".sql", ".yaml")
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
