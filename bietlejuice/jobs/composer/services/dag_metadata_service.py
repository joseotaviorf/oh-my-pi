import re
from typing import Dict, Optional, Tuple, Set, List

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.dags import COMPOSER_DAGS_PATH
from bietlejuice.jobs.composer.services import ConfigurationService

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

        # extract dag owner
        self._DAG_OWNER_REGEX = re.compile('"owner": ([\w.]*)[,|\n]?')

        # extract dag layers
        self._RAW_LAYER_MATCH_REGEX = re.compile(
            "build_raw_task_group_for_all_tables|build_raw_task_group_for_single_table|sync-hive-metastore-raw"
        )
        self._CLEAN_LAYER_MATCH_REGEX = re.compile(
            "sync-hive-metastore-clean|build_clean_task_group"
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
            r"sync_metastore_tables_structure\.py.*?\"parameters\": ?\[(.*?)]",
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

    def _get_dag_file_path(self, source: str, context: str, dag_name: str):
        intermediate_path = self._get_intermediate_path(source, context)
        if intermediate_path:
            return f"{COMPOSER_DAGS_PATH}/{intermediate_path}/{dag_name}.py"
        else:
            return f"{COMPOSER_DAGS_PATH}/{source}/{dag_name}.py"

    def _read_dag_file(self, source: str, context: str, dag_name: str):
        path = self._get_dag_file_path(source, context, dag_name)
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
        match = re.search(self._DAG_PATH_REGEX, dag_path).groupdict()
        source = match["source"]
        context = match["context"]
        dag = match["dag"]
        if not context:
            context = source
        return source, context, dag

    def dag_has_lineage_from_product_config(
        self, source: str, context: str, dag_name: str, env: str
    ) -> bool:
        """
        Checks if a dag has a valid lineage from product configuration
        :param source: The DAG source
        :param context: The DAG context
        :param dag_name:  The DAG name
        :param env: The environment to check for the variable
        :return: True if it has a confif, else False
        :rtype: bool
        """
        intermediate_path = self._get_intermediate_path(source, context)

        configs = ConfigurationService(
            dag_name, intermediate_path=intermediate_path, env=env
        )
        try:
            configs.get_config("lineage_product_database_name")
            return True
        except IndexError:
            return False

    def get_dag_owner(self, source: str, context: str, dag_name: str) -> Optional[str]:
        """
        Finds the dag owner defined in a dag source code
        :param source: dag source
        :param context: dag context
        :param dag_name: dag name
        :return: a string representing the dag owner or none, if not found
        """
        source_code = self._read_dag_file(source, context, dag_name)
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

            if LayerEnum.validate_layer(layer):
                layers.add(layer)
            else:
                logger.debug(f"m=get_dag_layers, layer={layer}, msg=Invalid Layer")
        return layers

    def get_dag_layers(
        self, source: str, context: str, dag_name: str, ignore_staging: bool = True
    ) -> List[str]:
        """
        Finds all layers used in a dag. May extract information simply from dag name or read the source code
        :param source: dag source
        :param context: dag context
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
            source_code = self._read_dag_file(source, context, dag_name)
            return list(self._get_layer_from_source_code(source_code, ignore_staging))

    def _get_dag_target_database_name(
        self, source: str, context: str, dag_name: str
    ) -> Optional[str]:
        """
        Finds the string value used as target_database_name in a dag. If more than one is found, returns only the first.
        :param source: dag source
        :param context: dag context
        :param dag_name: dag name
        :return: the string value used as target_database_name
        """
        source_code = self._read_dag_file(source, context, dag_name)

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
                    f"m=_get_dag_target_database_name, source={source}, context={context}, dag_name={dag_name}, "
                    f"target_dbs={target_dbs}, msg=Found more than 1 target db name "
                )

            return list(target_dbs)[0]
        else:
            return None

    def get_dag_database_name(
        self, source: str, context: str, dag_name: str, layer: str
    ) -> Optional[str]:
        """
        Find the spark database name used in a dag for a given layer.
        :param source: dag source
        :param context: dag context
        :param dag_name: dag name
        :param layer: the datalake layer of interest
        :return: a string with the database name or None if not found
        """
        if dag_name in self._DAG_MANUAL_MAPPING:
            return self._DAG_MANUAL_MAPPING[dag_name][layer]["database_name"]

        target_db_name = self._get_dag_target_database_name(source, context, dag_name)
        if not target_db_name:
            return None
        try:
            LayerEnum.validate_layer(layer)
        except ValueError:
            logger.info(
                f"m=get_dag_database_name, source={source}, context={context}, dag_name={dag_name}, layer={layer}, "
                f"msg=Invalid layer "
            )
            return None

        if layer == "dw":
            return f"dw_{target_db_name}"
        elif layer == "enrich":
            return f"datalake_{target_db_name}"
        elif layer in {"clean", "raw"}:
            return f"datalake_{target_db_name}_{layer}"
        else:
            return None
