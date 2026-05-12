from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
    DAGDeclarationValidator,
)
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.file_service import FileService


class DAGYamlParser:
    """Loads the DAG's metadata from a DAG declaration file."""

    def __init__(self, dag_name: str) -> None:
        self.__dag_name = dag_name

    def dag_declaration(self) -> dict:
        dag_declaration_file_path = DAGPackagesPathService.generate_artifact_file_path(
            artifact_type="dag_declaration", dag_name=self.__dag_name
        )
        dag_declaration = FileService.get_dict_from_yaml_file(dag_declaration_file_path)
        DAGDeclarationValidator().validate(dag_declaration=dag_declaration)

        return dag_declaration
