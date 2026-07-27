from functools import lru_cache
from os import stat
from typing import Optional, Tuple

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_cluster_validator import (
    DAGClusterValidator,
)
from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
    DAGDeclarationValidator,
)
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.file_service import FileService


def load_cluster_file(cluster_file_path: str) -> Tuple[dict, Optional[dict]]:
    """Load cluster config and its optional validation block."""
    cluster_doc = FileService.get_dict_from_yaml_file(cluster_file_path)
    if not isinstance(cluster_doc, dict):
        raise AssertionError(
            "m=dag_declaration, msg=Cluster file must be a YAML mapping with a "
            f"top-level 'cluster' key: {cluster_file_path!r}"
        )
    cluster_section = cluster_doc.get("cluster")
    if cluster_section is None:
        raise AssertionError(
            "m=dag_declaration, msg=Expected top-level 'cluster' key in "
            f"cluster file {cluster_file_path!r}"
        )
    return cluster_section, cluster_doc.get("validation")


def resolve_validation_block(
    raw_declaration: dict, validation_from_cluster: Optional[dict]
) -> Optional[dict]:
    """Resolve validation config; the split cluster file takes precedence."""
    if validation_from_cluster is not None:
        return validation_from_cluster
    return raw_declaration.get("validation")


def _file_mtime_ns(file_path: Optional[str]) -> Optional[int]:
    if file_path is None:
        return None
    try:
        return stat(file_path).st_mtime_ns
    except OSError:
        # Preserve the parser's existing FileNotFoundError/error message path.
        return None


@lru_cache(maxsize=1024)
def _parse_dag_declaration_cached(
    dag_name: str,
    dag_declaration_file_path: str,
    declaration_mtime_ns: Optional[int],
    dag_cluster_file_path: Optional[str],
    cluster_mtime_ns: Optional[int],
) -> dict:
    """Parse one declaration, keyed by both paths and modification times.

    The mtime arguments are intentionally unused by the body: they form the
    cache key so a dags-only deployment invalidates manager-prewarmed values
    without requiring the dag-processor to restart.
    """
    del declaration_mtime_ns, cluster_mtime_ns
    expected_cluster_path = DAGPackagesPathService.generate_artifact_file_path(
        artifact_type="dag_cluster", dag_name=dag_name, add_default_ext=False
    )
    raw_declaration = FileService.get_dict_from_yaml_file(dag_declaration_file_path)
    legacy_cluster = raw_declaration.pop("cluster", None)

    if dag_cluster_file_path is not None:
        cluster_section, validation_from_cluster = load_cluster_file(
            dag_cluster_file_path
        )
    else:
        cluster_section = legacy_cluster
        if cluster_section is None:
            raise AssertionError(
                "m=dag_declaration, msg=Missing cluster configuration: add "
                f"{expected_cluster_path}.yml (or .yaml) or define 'cluster' in "
                "the declaration file"
            )
        validation_from_cluster = None

    declaration_to_validate = {**raw_declaration}
    validation = resolve_validation_block(raw_declaration, validation_from_cluster)
    if validation is not None:
        declaration_to_validate["validation"] = validation

    declaration_validator = DAGDeclarationValidator()
    declaration_validator.validate(dag_declaration=declaration_to_validate)

    merged = {**declaration_to_validate, "cluster": cluster_section}
    declaration_validator.validate_cluster_validation_cluster_diff(
        dag_declaration=merged
    )
    DAGClusterValidator().validate_cluster(dag_declaration=merged)
    return merged


def _parse_dag_declaration(dag_name: str) -> dict:
    """Resolve file versions, then return the matching cached declaration."""
    dag_declaration_file_path = DAGPackagesPathService.generate_artifact_file_path(
        artifact_type="dag_declaration", dag_name=dag_name
    )
    dag_cluster_file_path = DAGPackagesPathService.resolve_artifact_file_path(
        artifact_type="dag_cluster", dag_name=dag_name
    )
    declaration_mtime_ns = _file_mtime_ns(dag_declaration_file_path)
    cluster_mtime_ns = _file_mtime_ns(dag_cluster_file_path)
    return _parse_dag_declaration_cached(
        dag_name,
        dag_declaration_file_path,
        declaration_mtime_ns,
        dag_cluster_file_path,
        cluster_mtime_ns,
    )


_parse_dag_declaration.cache_clear = _parse_dag_declaration_cached.cache_clear
_parse_dag_declaration.cache_info = _parse_dag_declaration_cached.cache_info


class DAGYamlParser:
    """Loads the DAG's metadata from DAG declaration and cluster YAML files."""

    def __init__(self, dag_name: str) -> None:
        self.__dag_name = dag_name

    @staticmethod
    def _load_cluster_file(cluster_file_path: str) -> Tuple[dict, Optional[dict]]:
        return load_cluster_file(cluster_file_path)

    def dag_declaration(self) -> dict:
        """Parse and validate the DAG declaration YAML, cached by DAG name."""
        return _parse_dag_declaration(self.__dag_name)
