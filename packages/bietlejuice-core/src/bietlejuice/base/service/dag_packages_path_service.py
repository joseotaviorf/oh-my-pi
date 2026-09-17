import logging
import os
import re
from functools import lru_cache
from glob import glob
from os import path, scandir
from typing import Dict, Optional, Set

from hierarchical_conf.hierarchical_conf import HierarchicalConf

from bietlejuice.base.caching import PARSE_CACHE_MAXSIZE
from bietlejuice.base.paths import BIETLEJUICE_CONFIG_ROOT, DAG_PACKAGES_ROOT

_LOG = logging.getLogger(__name__)


class DataQualityLayerCache:
    """Per-instance, per-layer cache of data quality file paths for parse-time performance.

    After changes to path resolution or listing (e.g. ``list_data_quality_table_paths_in_composer``),
    run a Composer smoke test that parses DAGs which reference many data-quality YAMLs so regressions
    surface before production.
    """

    def __init__(self, dag_name: str) -> None:
        self._dag_name = dag_name
        self._cache: Dict[str, Set[str]] = {}

    def get(self, layer: str) -> Set[str]:
        if layer not in self._cache:
            self._cache[layer] = (
                DAGPackagesPathService.list_data_quality_table_paths_in_composer(
                    self._dag_name, layer
                )
            )
        return self._cache[layer]


class DAGPackagesPathService:
    """
    Abstracts and centralizes path/directory manipulations related to the DAGs or its inner contents.

    The methods are annotated, so we know if they can be used in Databricks or Composer to avoid errors
     and after migration we can easily uncouple the code between Orchestration and Jobs Core code.

    Performance-related behavior (``@lru_cache`` on ``get_dag_path``, ``DataQualityLayerCache``, and
    helpers that scan data-quality paths) affects Composer DAG parsing and any code that walks many
    DQ YAMLs. After substantive edits here, smoke-test DAG parse in Composer (or equivalent checks
    that load many declarations and DQ files) to catch regressions.
    """

    __EXTENSIONS = {
        "dag_declaration": ["yml", "yaml"],
        "dag_cluster": ["yml", "yaml"],
        "data_quality": ["yml", "yaml"],
        "metadata": ["yml", "yaml"],
        "configuration_file": ["yml", "yaml"],
        "doc_md": ["md"],
        "query": ["sql"],
    }

    __FILE_SUFFIXES = {
        "dag_declaration": "_declaration",
        "dag_cluster": "_cluster",
        "configuration_file": "_conf",
    }

    __FILE_NAME_TEMPLATES = {
        "dag_declaration": "{dag_name}{file_suffix}",
        "dag_cluster": "{dag_name}{file_suffix}",
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

    _line_folders_cache = None

    @staticmethod
    def _get_line_folders():
        """Return the list of top-level domain folders under the DAG packages tree.

        In Airflow/Composer, ``DAG_PACKAGES_ROOT`` is the filesystem path to the
        ``dags/`` directory, and the result is obtained by ``scandir``.

        In Databricks, ``DAG_PACKAGES_ROOT`` is ``None`` because the ``dags``
        package is not on ``sys.path``. In that case the method falls back to the
        Databricks Volume mount: it reads ``volume_databricks_bucket`` and
        ``dags_packages_files_path_in_s3`` from the bietlejuice config and scans
        ``{volume}/{prefix}dags/`` — the same path layout used by
        ``_read_dag_package_file_from_s3``.  Any config/IO error is swallowed and
        an empty list is returned so callers fall through to the S3/volume loaders.

        The result is cached for the lifetime of the current process. In the
        standard Airflow 2.x parse path each DAG file is processed in a fresh
        subprocess, so the cache is effectively reset per parse cycle and
        staleness is not a concern.

        For long-running processes (e.g. a DagBag loaded in a webserver worker)
        call ``DAGPackagesPathService.clear_path_caches()`` before re-scanning
        if a new domain folder has been added since the process started.
        """
        if DAGPackagesPathService._line_folders_cache is not None:
            return DAGPackagesPathService._line_folders_cache

        if DAG_PACKAGES_ROOT:
            DAGPackagesPathService._line_folders_cache = list(
                scandir(DAG_PACKAGES_ROOT)
            )
            return DAGPackagesPathService._line_folders_cache

        # Databricks: resolve the dags/ tree from the Volume mount.
        try:
            global_confs = HierarchicalConf([BIETLEJUICE_CONFIG_ROOT])
            volume = global_confs.get_config("volume_databricks_bucket")
            prefix = global_confs.get_config("dags_packages_files_path_in_s3")
            dags_root = path.join(volume, prefix, "dags")
            if path.isdir(dags_root):
                DAGPackagesPathService._line_folders_cache = list(scandir(dags_root))
                return DAGPackagesPathService._line_folders_cache
        except Exception:  # noqa: BLE001 — config may be absent outside Databricks
            pass

        DAGPackagesPathService._line_folders_cache = []
        return DAGPackagesPathService._line_folders_cache

    @classmethod
    def get_dag_domain_names(cls) -> list:
        """
        Return top-level domain folder names under DAG_PACKAGES_ROOT.

        Discovered automatically via filesystem scan. Skips non-directories
        and hidden/internal entries (e.g. __pycache__).
        """
        return [
            e.name
            for e in cls._get_line_folders()
            if e.is_dir() and not e.name.startswith("_")
        ]

    @classmethod
    def clear_path_caches(cls) -> None:
        """Clear all process-scoped path caches in one call.

        Both ``_line_folders_cache`` and the ``get_dag_path``,
        ``list_data_quality_table_paths_in_composer``,
        ``list_queries_files_in_composer``, and DAG declaration parse caches
        are intentionally process-scoped for parse-time performance. In the
        normal Airflow 2.x parse flow (one subprocess per DAG file) they reset
        automatically on each parse cycle.

        Call this method from a long-running process (e.g. a DagBag reload in
        the webserver) when DAG folders have been added or removed and a fresh
        filesystem scan is needed.
        """
        cls._line_folders_cache = None
        cls.get_dag_path.cache_clear()
        cls.list_data_quality_table_paths_in_composer.cache_clear()
        cls.list_queries_files_in_composer.cache_clear()

        from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
            _parse_dag_declaration,
        )

        _parse_dag_declaration.cache_clear()

    @staticmethod
    def _find_dag_in_line_folders(dag_name):
        """
        Finds DAG folder by traversing between all lines folders.

        Skips hidden/internal top-level entries (name starts with ``_``), matching
        ``get_dag_domain_names``. Otherwise Astro domain-bundle dirs under
        ``dags/_astro_bundles/<domain>/`` collide with DAGs named like their
        domain (e.g. ``journey_optimizer/journey_optimizer``).

        :param dag_name: DAG name.
        :return: DAG folder path.
        """
        for line_folder in DAGPackagesPathService._get_line_folders():
            if not line_folder.is_dir() or line_folder.name.startswith("_"):
                continue
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
        except OSError as e:
            raise RuntimeError(
                f"m=_read_file_content_from_filesystem, file_name={file_path},"
                f" msg=File not found, error={e}"
            )

    @staticmethod
    def _manifest_is_fresh(
        manifest_path: str, source_dir: str, recursive_dirs: bool = False
    ) -> bool:
        """
        Return whether a manifest is newer than the directory structure it indexes.

        We only need to detect add/remove/rename events, so directory mtimes are
        enough and avoid a full file glob before using the manifest.
        """
        if os.environ.get("BIETLEJUICE_TRUST_MANIFESTS", "").strip() == "1":
            return True

        try:
            manifest_mtime = path.getmtime(manifest_path)
            dirs_to_check = [source_dir]
            while dirs_to_check:
                current_dir = dirs_to_check.pop()
                if path.getmtime(current_dir) > manifest_mtime:
                    _LOG.debug(
                        "Ignoring stale manifest; falling back to filesystem scan: %s",
                        manifest_path,
                    )
                    return False
                if not recursive_dirs:
                    continue
                with scandir(current_dir) as entries:
                    for entry in entries:
                        if entry.is_dir():
                            dirs_to_check.append(entry.path)
        except FileNotFoundError:
            _LOG.debug(
                "Manifest or source directory disappeared; falling back to "
                "filesystem scan: %s",
                manifest_path,
            )
            return False
        return True

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
            SparkFiles.get(sql_file_key.split("/")[-1]), encoding="utf-8"
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

        with open(f"{volume}/{sql_file_key}", encoding="utf-8") as f:
            query = f.read()
        return query

    @staticmethod
    def _read_file_from_s3_boto3(bucket: str, sql_file_key: str):
        """
        Read a file from the s3
        """
        import boto3

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

        global_confs = HierarchicalConf([BIETLEJUICE_CONFIG_ROOT])
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
    @lru_cache(maxsize=PARSE_CACHE_MAXSIZE)
    def get_dag_path(dag_name: str) -> str:
        """
        Gets the DAG's full path.

        The path returned does not contain a trailing slash, e.g. ``/dags/for_rent/my_dag``.

        * Method used only in Composer *

        Finds the DAG path according to its location: inside the DAG Packages or
        in the legacy path (bietlejuice).

        Result is cached via ``@lru_cache`` for the lifetime of the current
        process. This is safe in the standard Airflow 2.x parse flow (fresh
        subprocess per DAG file). For long-running processes, call
        ``DAGPackagesPathService.clear_path_caches()`` to invalidate both this
        cache and ``_line_folders_cache`` together.

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
        legacy path or in the DAGs packages).

        Used from Spark driver jobs (Databricks or EMR). When ``SPARK_RUNTIME=emr``,
        S3 reads always use ``boto3`` regardless of ``engine`` (Databricks volume and
        Spark-based readers are not used on EMR).

        :param dag_name: the DAG name
        :param table_name: the name of the table that the file is related to
        :param layer: the layer that the file is related to.
        :param intermediate_path: off intermediate path structure used in some DAGs
        :param engine: engine on Databricks: "spark", "boto3" or "databricks_volume". On EMR, boto3 is always used.
        :return: query content (the SQL)
        """
        from bietlejuice.base.spark.runtime_detector import RuntimeDetector

        if RuntimeDetector.is_emr():
            engine = "boto3"

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
    def get_config_file_content_in_spark_jobs(
        dag_name: str,
        file_name: str,
        engine: str = "databricks_volume",
    ) -> str:
        """
        Opens a co-located configuration file shipped under ``spark_jobs/{dag_name}/``.

        Used from Spark driver jobs (Databricks or EMR) that read an in-repo config
        (e.g. an alert registry YAML) living next to the custom job ``.py``. When
        ``SPARK_RUNTIME=emr``, S3 reads always use ``boto3`` regardless of ``engine``.

        :param dag_name: the DAG name
        :param file_name: the config file name co-located under spark_jobs/{dag_name}/
        :param engine: engine on Databricks: "spark", "boto3" or "databricks_volume". On EMR, boto3 is always used.
        :return: config file content
        """
        from bietlejuice.base.spark.runtime_detector import RuntimeDetector

        if RuntimeDetector.is_emr():
            engine = "boto3"

        config_file_relative_path = path.join("spark_jobs", dag_name, file_name)
        config_content = DAGPackagesPathService._read_dag_package_file_from_s3(
            sql_file_relative_path=config_file_relative_path, engine=engine
        )

        if not config_content:
            raise FileNotFoundError(
                f"Config file was not found or is empty, dag_name={dag_name}, config_file_relative_path={config_file_relative_path}"
            )

        return config_content

    QUERY_MANIFEST_FILENAME = ".table_manifest"

    @staticmethod
    @lru_cache(maxsize=PARSE_CACHE_MAXSIZE)
    def list_queries_files_in_composer(
        dag_name: str, layer: str, intermediate_path: str = ""
    ) -> tuple:
        """
        Lists all query files for a given DAG and layer.

        * Method used only in Composer *

        :param dag_name: The DAG we want to list the D.Q. files.
        :param layer: the layer that the file is related to.
        :param intermediate_path: off intermediate path structure used in some DAGs
        :return: tuple of queries files without file extension (only table names)
        """
        sql_files_folder = path.join(
            DAGPackagesPathService.get_dag_path(dag_name),
            "queries",
            layer,
            intermediate_path,
        )

        manifest_path = path.join(
            sql_files_folder, DAGPackagesPathService.QUERY_MANIFEST_FILENAME
        )
        if path.isfile(manifest_path) and DAGPackagesPathService._manifest_is_fresh(
            manifest_path, sql_files_folder
        ):
            with open(manifest_path) as f:
                table_names = [line.strip() for line in f if line.strip()]
            return tuple(sorted(table_names))

        filename_regex = re.compile(r"([a-z0-9_-]+)\.sql")
        files = glob(f"{sql_files_folder}/*.sql")
        table_names = []
        for file_path in files:
            table_names.append(re.search(filename_regex, file_path).group(1))

        return tuple(table_names)

    @staticmethod
    def get_data_quality_file_content_in_spark_jobs(
        dag_name: str,
        table_name: str,
        layer: str,
        intermediate_path: str,
        engine: str = "databricks_volume",
    ):
        """
        Opens the Data Quality file according to the place it is stored (if it is in
         legacy path or in the DAGs packages).

        Used from Spark driver jobs (Databricks or EMR). When ``SPARK_RUNTIME=emr``,
        S3 reads always use ``boto3`` regardless of ``engine``.

        :param dag_name: the DAG name
        :param layer: the layer that the file is related to.
        :param table_name: the name of the table that the file is related to
        :param intermediate_path: off intermediate path structure used in some DAGs
        :param engine: engine on Databricks: "spark", "boto3" or "databricks_volume". On EMR, boto3 is always used.
        :return: the data quality content
        """
        from bietlejuice.base.spark.runtime_detector import RuntimeDetector

        if RuntimeDetector.is_emr():
            engine = "boto3"

        data_quality_file_path = path.join(
            "data_quality", dag_name, layer, intermediate_path, f"{table_name}.yml"
        )

        try:
            data_quality_content = (
                DAGPackagesPathService._read_dag_package_file_from_s3(
                    sql_file_relative_path=data_quality_file_path,
                    engine=engine,
                )
            )
        except Exception as e:
            if "NoSuchKey" in str(e):
                data_quality_content = (
                    DAGPackagesPathService._read_dag_package_file_from_s3(
                        sql_file_relative_path=data_quality_file_path.replace(
                            "yml", "yaml"
                        ),
                        engine=engine,
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

    DATA_QUALITY_MANIFEST_FILENAME = ".data_quality_manifest"

    @staticmethod
    @lru_cache(maxsize=PARSE_CACHE_MAXSIZE)
    def list_data_quality_table_paths_in_composer(dag_name: str, layer: str) -> set:
        """
        Returns set of relative paths (without ext) for tables that have data quality files.
        Used for batch file-existence checks during DAG parse. Supports nested paths.
        Reads .data_quality_manifest when present (avoids glob over many files).
        """
        dag_path = DAGPackagesPathService.get_dag_path(dag_name)
        data_quality_folder = path.join(dag_path, "data_quality", layer)
        if not path.isdir(data_quality_folder):
            return set()
        manifest_path = path.join(
            data_quality_folder, DAGPackagesPathService.DATA_QUALITY_MANIFEST_FILENAME
        )
        if path.isfile(manifest_path) and DAGPackagesPathService._manifest_is_fresh(
            manifest_path, data_quality_folder, recursive_dirs=True
        ):
            result = set()
            with open(manifest_path) as f:
                for line in f:
                    name = line.strip()
                    if name:
                        result.add(path.normpath(name))
            return result
        files = glob(f"{data_quality_folder}/**/*.yml", recursive=True) + glob(
            f"{data_quality_folder}/**/*.yaml", recursive=True
        )
        result = set()
        for file_path in files:
            rel = path.relpath(file_path, data_quality_folder)
            result.add(path.normpath(path.splitext(rel)[0]))
        return result

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
            file_path_ext = f"{file_path}.{ext}"
            extensions_validation.append(path.isfile(file_path_ext))

        return any(extensions_validation)

    @classmethod
    def resolve_artifact_file_path(
        cls, artifact_type: str, dag_name: str, layer: str = "", table_name: str = ""
    ) -> Optional[str]:
        """
        Returns the on-disk path for an artifact when it exists, checking all
        supported extensions in ``__EXTENSIONS`` order.

        :return: Resolved file path, or ``None`` when no matching file exists.
        """
        for ext in cls.__EXTENSIONS[artifact_type]:
            file_path = cls.generate_artifact_file_path(
                artifact_type, dag_name, layer, table_name, add_default_ext=False
            )
            file_path_ext = f"{file_path}.{ext}"
            if path.isfile(file_path_ext):
                return file_path_ext
        return None

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
            file_name = f"{file_name}.{cls.__EXTENSIONS[artifact_type][0]}"
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
            if not DAG_PACKAGES_ROOT:
                return None
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
