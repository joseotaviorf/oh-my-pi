import glob
import os
import re
from functools import lru_cache
from typing import Dict, List, Optional, Set, Tuple

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.caching import PARSE_CACHE_MAXSIZE
from bietlejuice.base.db.datalake_metastore_mapping import apply_naming_convention
from bietlejuice.base.paths import DAG_PACKAGES_ROOT, DATALAKE_METADATA_PATH
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.configuration_service import ConfigurationService

logger = QuintoAndarLogger("DAGMetadataService")


class DAGMetadataService:
    """
    Service to extract DAG informations suchs as:
        - what layers this DAG refers to
        - what databases this dag refers to
        - if this dag has a lineage from product configuration
    etc.
    """

    def __init__(self, dag_manual_mapping: Dict[str, Dict[str, Dict[str, str]]] = None):
        self._STAGING_LAYERS = {
            LayerEnum.DW_STAGING.value,
            LayerEnum.CLEAN_STAGING.value,
        }

        # general operations
        self._DAG_PATH_REGEX = re.compile(
            r"dags/(?P<source>\w+)(?:/(?P<context>\w+))?/(?P<dag>\w+)\.py"
        )

        # Regex that contains dag package and dag legacy path
        self._DAG_PACKAGE_REGEX = re.compile(
            r"dags/(.*/)?(?P<source>\w+)(?:/(?P<context>\w+))?/(?P<dag>\w+)\.py"
        )

        # extract dag owner
        self._DAG_OWNER_REGEX = re.compile(r'"owner": ([\w.]*)[,|\n]?')

        # extract dag layers
        self._RAW_LAYER_MATCH_REGEX = re.compile(
            "build_raw_task_group_for_all_tables|build_raw_task_group_for_single_table|sync-hive-metastore-raw|sync-metadata-raw"
        )
        self._CLEAN_LAYER_MATCH_REGEX = re.compile(
            "sync-hive-metastore-clean|build_clean_task_group|sync-metadata-clean"
        )
        self._BUILD_TASK_GROUP_LAYER_REGEX = re.compile(
            r"build_task_group_from_sql_files.*?layer ?= ?LayerEnum\.(\w+)",
            flags=re.DOTALL,
        )

        # extract dag database_name
        self._GENERIC_TARGET_DATABASE_NAME = re.compile(
            r"target_database_base_name ?= ?(\w+)"
        )
        self._DW_TASK_GROUP_SCHEMA = re.compile(
            r"DWTaskGroup.*?dw_schema ?= ?(\w*)", flags=re.DOTALL
        )
        self._SYNC_METASTORE_PARAMETERS = re.compile(
            r"sync_metadata\.py.*?\"parameters\": ?\[(.*?)]|sync_metastore_tables_structure\.py.*?\"parameters\": ?\[(.*?)]",
            flags=re.DOTALL,
        )

        # manually map dags to its layers and database names
        self._DAG_MANUAL_MAPPING = dag_manual_mapping or None

    def _get_intermediate_path(self, source: str, context: str):
        if source == context:
            intermediate_path = None
        else:
            intermediate_path = f"{source}/{context}"
        return intermediate_path

    def _get_dag_file_path(self, dag_name: str):
        dag_packages_path = glob.glob(
            f"{DAG_PACKAGES_ROOT}/**/{dag_name}.py", recursive=True
        )
        return dag_packages_path[0]

    def _read_dag_file(self, dag_name: str):
        path = self._get_dag_file_path(dag_name)
        with open(path) as fp:
            dag_code = fp.read()
        return dag_code

    def _find_var_value(self, code, variable) -> Optional[str]:
        """
        Given a string with a source code and a variable name used in that code, recursively
        finds the string value attributed to that variable.
        :param code: a string representation of the source code
        :param variable: the name of the variable
        :return: a string with the value of that variable, or None if not found
        """
        string_attr = re.search(rf"{variable} ?= ?\"(\w+)\"", code)
        if string_attr:
            return string_attr.group(1)
        else:
            new_var = re.search(rf"{variable} ?= ?(\w+)", code)
            if new_var:
                return self._find_var_value(code, new_var.group(1))
            else:
                return None

    def get_dag_info_from_path(self, dag_path: str) -> Tuple[str, str, str]:
        """
        Extracts source, context and dag name from the path to a dag file
        :param dag_path: path to dag file
        :return: tuple with source, context, and dag name
        """
        # TODO: remove after dag packages migration finishes.
        match = re.search(self._DAG_PACKAGE_REGEX, dag_path).groupdict()
        source = match["source"]
        context = match["context"]
        dag = match["dag"]

        if not context:
            context = source
        return source, context, dag

    def dag_has_lineage_from_product_config(
        self, source: str, context: str, dag_name: str
    ) -> bool:
        """
        Checks if a dag has a valid lineage from product configuration
        :param source: The DAG source
        :param context: The DAG context
        :param dag_name:  The DAG name
        :return: True if it has a confif, else False
        :rtype: bool
        """
        intermediate_path = self._get_intermediate_path(source, context)

        configs = ConfigurationService(dag_name, intermediate_path=intermediate_path)
        try:
            configs.get_config("lineage_product_database_name")
            return True
        except IndexError:
            return False

    def get_dag_owner(self, dag_name: str) -> Optional[str]:
        """
        Finds the dag owner defined in a dag source code
        :param dag_name: dag name
        :return: a string representing the dag owner or none, if not found
        """
        source_code = self._read_dag_file(dag_name)
        match = re.search(self._DAG_OWNER_REGEX, source_code)
        if match:
            return match.group(1)
        else:
            return None

    def _get_layer_from_source_code(
        self, source_code: str, ignore_staging: bool = True
    ) -> Set[str]:
        """
        Finds all layers used in a dag source code
        :param source_code: str representation of the dag source code
        :param ignore_staging: if true, does not returns staging layers (clean_staging and dw_staging)
        :return: a set with strings representing all layers used in dag
        """
        layers = set()

        raw_match = re.search(self._RAW_LAYER_MATCH_REGEX, source_code)
        if raw_match:
            layers.add("raw")

        clean_match = re.search(self._CLEAN_LAYER_MATCH_REGEX, source_code)
        if clean_match:
            layers.add("clean")

        build_task_group_layers = [
            layer.lower()
            for layer in re.findall(self._BUILD_TASK_GROUP_LAYER_REGEX, source_code)
        ]

        for layer in build_task_group_layers:
            if ignore_staging and layer in self._STAGING_LAYERS:
                continue

            if layer in LayerEnum.get_available_enum_values():
                layers.add(layer)
            else:
                logger.debug(f"m=get_dag_layers, layer={layer}, msg=Invalid Layer")
        return layers

    def get_dag_layers(self, dag_name: str, ignore_staging: bool = True) -> List[str]:
        """
        Finds all layers used in a dag. May extract information simply from dag name or read the source code
        :param dag_name: dag name
        :param ignore_staging: if true, does not returns staging layers (clean_staging and dw_staging)
        :return: a set with strings representing all layers used in dag
        """
        if dag_name in self._DAG_MANUAL_MAPPING:
            return list(self._DAG_MANUAL_MAPPING[dag_name].keys())

        if dag_name.startswith("dw_"):
            return ["dw"]
        elif dag_name.startswith("enrich_"):
            return ["enrich"]
        else:
            source_code = self._read_dag_file(dag_name)
            return list(self._get_layer_from_source_code(source_code, ignore_staging))

    def _get_dag_target_database_name(self, dag_name: str) -> Optional[str]:
        """
        Finds the string value used as target_database_name in a dag. If more than one is found, returns only the first.
        :param dag_name: dag name
        :return: the string value used as target_database_name
        """
        source_code = self._read_dag_file(dag_name)

        datalake_dbs_vars = set(
            re.findall(self._GENERIC_TARGET_DATABASE_NAME, source_code)
        )
        dw_dbs_vars = set(re.findall(self._DW_TASK_GROUP_SCHEMA, source_code))
        sync_params_vars = re.search(self._SYNC_METASTORE_PARAMETERS, source_code)

        target_db_vars = set()
        # create a set with vars used as target_db in dag
        if datalake_dbs_vars:
            for dl_var in datalake_dbs_vars:
                target_db_vars.add(dl_var)
        elif dw_dbs_vars:
            for dw_var in dw_dbs_vars:
                target_db_vars.add(dw_var)
        elif sync_params_vars:
            sync_params = (
                sync_params_vars.group(1).replace("\n", "").replace(" ", "").split(",")
            )
            target_db_vars.add(sync_params[2])

        # evaluate those vars
        target_dbs = {
            self._find_var_value(source_code, target_db_var)
            for target_db_var in target_db_vars
        }

        if target_dbs:
            if len(target_dbs) > 1:
                logger.info(
                    f"m=_get_dag_target_database_name, dag_name={dag_name}, "
                    f"target_dbs={target_dbs}, msg=Found more than 1 target db name "
                )

            return list(target_dbs)[0]
        else:
            return None

    def get_dag_database_name(self, dag_name: str, layer: str) -> Optional[str]:
        """
        Find the spark database name used in a dag for a given layer.
        :param dag_name: dag name
        :param layer: the datalake layer of interest
        :return: a string with the database name or None if not found
        """
        if dag_name in self._DAG_MANUAL_MAPPING:
            return self._DAG_MANUAL_MAPPING[dag_name][layer]["database_name"]

        target_db_name = self._get_dag_target_database_name(dag_name)
        if not target_db_name:
            return None
        try:
            LayerEnum(layer)
        except ValueError:
            logger.info(
                f"m=get_dag_database_name, dag_name={dag_name}, layer={layer}, "
                f"msg=Invalid layer "
            )
            return None

        if layer == "dw":
            return f"dw_{target_db_name}"
        elif layer == "enrich":
            return apply_naming_convention(target_db_name, f"datalake_{target_db_name}")
        elif layer in {"clean", "raw"}:
            return apply_naming_convention(
                target_db_name, f"datalake_{target_db_name}_{layer}"
            )
        else:
            return None

    @staticmethod
    def get_all_dag_metadata_files(dag_name: str) -> List:
        # TODO: this method and the other metadata methods in this class with rules out
        #  of the FileServices context must be replaced to another place like some Metadata Service
        dag_path = DAGPackagesPathService.get_dag_path(dag_name)
        path = f"{dag_path}/metadata/**/*.*"
        files_found = glob.glob(path, recursive=True)

        if not files_found:
            path = f"{DATALAKE_METADATA_PATH}/{dag_name}"
            files_found = glob.glob(path, recursive=True)

        return files_found

    @staticmethod
    def get_dag_metadata_file(dag_name: str, layer: str, table_name: str) -> List:
        # TODO: this method and the other metadata methods in this class with rules out
        #  of the FileServices context must be replaced to another place like some Metadata Service
        dag_path = DAGPackagesPathService.get_dag_path(dag_name)
        path = f"{dag_path}/metadata/{layer}/**/{table_name}.*"  # Para Databricks: pegar do S3.
        files_found = glob.glob(path, recursive=True)

        if not files_found:
            path = f"{DATALAKE_METADATA_PATH}/{dag_name}/{layer}/**/{table_name}.*"
            files_found = glob.glob(path, recursive=True)

        return files_found

    METADATA_MANIFEST_FILENAME = ".metadata_manifest"

    @staticmethod
    @lru_cache(maxsize=PARSE_CACHE_MAXSIZE)
    def list_metadata_table_paths(dag_name: str, layer: str) -> Set[str]:
        """
        Returns set of relative paths (without ext) for tables that have metadata files.
        Used for batch existence checks to avoid per-table filesystem I/O.
        Reads .metadata_manifest when present (avoids glob over many files).
        """
        dag_path = DAGPackagesPathService.get_dag_path(dag_name)
        result = set()
        if dag_path is None:
            return result
        metadata_layer_path = os.path.join(dag_path, "metadata", layer)
        if os.path.isdir(metadata_layer_path):
            manifest_path = os.path.join(
                metadata_layer_path, DAGMetadataService.METADATA_MANIFEST_FILENAME
            )
            if os.path.isfile(
                manifest_path
            ) and DAGPackagesPathService._manifest_is_fresh(
                manifest_path, metadata_layer_path, recursive_dirs=True
            ):
                with open(manifest_path) as f:
                    for line in f:
                        name = line.strip()
                        if name:
                            result.add(os.path.normpath(name))
            else:
                pattern = os.path.join(metadata_layer_path, "**", "*")
                for file_path in glob.glob(pattern, recursive=True):
                    if os.path.isfile(file_path):
                        rel = os.path.relpath(file_path, metadata_layer_path)
                        name_without_ext = os.path.splitext(rel)[0]
                        result.add(name_without_ext)
        legacy_path = os.path.join(DATALAKE_METADATA_PATH, dag_name, layer)
        if os.path.isdir(legacy_path):
            pattern = os.path.join(legacy_path, "**", "*")
            for file_path in glob.glob(pattern, recursive=True):
                if os.path.isfile(file_path):
                    rel = os.path.relpath(file_path, legacy_path)
                    name_without_ext = os.path.splitext(rel)[0]
                    result.add(name_without_ext)
        return result

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
        # TODO: this method and the other metadata methods in this class with rules out
        #  of the FileServices context must be replaced to another place like some Metadata Service
        if check_all_tables:
            return bool(
                DAGMetadataService.get_all_dag_metadata_files(
                    dag_name=relative_file_path
                )
            )

        return bool(
            DAGMetadataService.get_dag_metadata_file(
                dag_name=relative_file_path, layer=layer, table_name=table_name
            )
        )
