from os.path import join

import pytest

from bietlejuice.base.files_validation.validators.yaml_validator import YamlValidator
from dags import DAG_PACKAGES_ROOT

DAG_DEPENDENCIES = [join(DAG_PACKAGES_ROOT, "dependencies.yaml")]


class TestDagDependencies:
    @pytest.mark.parametrize("file_path", DAG_DEPENDENCIES)
    def test_cyclic_dependencies(self, file_path):
        validator = YamlValidator(file_path)
        result = validator.run_validator(
            validation_method=validator.validate_cyclic_dependency
        )
        assert result, "There are cyclic dependencies in the YAML file."

    @pytest.mark.parametrize("file_path", DAG_DEPENDENCIES)
    def test_list_dependencies(self, file_path):
        validator = YamlValidator(file_path)
        result = validator.run_validator(
            validation_method=validator.validate_list_dependencies
        )
        assert result, (
            "The YAML file with the DAGs dependencies doesn't have the right structure. "
            "Please follow the examples inside the file."
        )
