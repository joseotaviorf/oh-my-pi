from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_cluster_validator import (
    DAGClusterValidator,
)
from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
    DAGDeclarationValidator,
)
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.file_service import FileService


class DAGYamlParser:
    """Loads the DAG's metadata from DAG declaration and cluster YAML files."""

    def __init__(self, dag_name: str) -> None:
        self.__dag_name = dag_name

    @staticmethod
    def _load_cluster_file(cluster_file_path: str) -> tuple[dict, dict | None]:
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

    def dag_declaration(self) -> dict:
        dag_declaration_file_path = DAGPackagesPathService.generate_artifact_file_path(
            artifact_type="dag_declaration", dag_name=self.__dag_name
        )
        dag_cluster_file_path = DAGPackagesPathService.resolve_artifact_file_path(
            artifact_type="dag_cluster", dag_name=self.__dag_name
        )
        expected_cluster_path = DAGPackagesPathService.generate_artifact_file_path(
            artifact_type="dag_cluster", dag_name=self.__dag_name, add_default_ext=False
        )
        raw_declaration = FileService.get_dict_from_yaml_file(dag_declaration_file_path)
        legacy_cluster = raw_declaration.pop("cluster", None)

        if dag_cluster_file_path is not None:
            cluster_section, validation_from_cluster = self._load_cluster_file(
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

        # validation: may live in the cluster file (preferred) or inline in the declaration
        # (legacy). Cluster-file value takes precedence when both are present.
        declaration_to_validate = {**raw_declaration}
        if validation_from_cluster is not None:
            declaration_to_validate["validation"] = validation_from_cluster

        declaration_validator = DAGDeclarationValidator()
        declaration_validator.validate(dag_declaration=declaration_to_validate)

        merged = {**declaration_to_validate, "cluster": cluster_section}
        declaration_validator.validate_cluster_validation_cluster_diff(
            dag_declaration=merged
        )
        DAGClusterValidator().validate_cluster(dag_declaration=merged)
        return merged
