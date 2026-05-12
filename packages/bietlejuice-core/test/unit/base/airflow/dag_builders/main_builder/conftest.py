import pytest

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
    DAGDeclarationValidator,
)
from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
    DAGYamlParser,
)


@pytest.fixture
def dag_declaration_validator():
    dag_declaration_validator = DAGDeclarationValidator()
    return dag_declaration_validator


@pytest.fixture()
def dag_yaml_parser():
    dag_yaml_parser = DAGYamlParser(dag_name="")
    return dag_yaml_parser
