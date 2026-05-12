import pytest


class TestYamlValidators:
    """
    Test yaml validators
    """

    @pytest.mark.parametrize(
        "yaml_content, required_fields",
        [
            (
                {"rule_id": {"query": "path_to_query.sql", "funnel_side": "demand"}},
                {"query", "funnel_side"},
            )
        ],
    )
    def test_yaml_keys_validator(
        self, yaml_content, required_fields, yaml_validator_mock
    ):
        """
        Test if validate_yaml_keys return True given that yaml content has all required columns
        :param yaml_content: yaml as dict
        :param required_fields: keys to be validated
        :param yaml_validator_mock: mock of YamlValidator declared in conftest
        """
        assert yaml_validator_mock.validate_yaml_keys(yaml_content, required_fields)

    @pytest.mark.parametrize(
        "yaml_content, required_fields",
        [
            (
                {"rule_id": {"query": "path_to_query.sql", "funnel_side": "demand"}},
                {"query", "side"},
            )
        ],
    )
    def test_yaml_missing_key_fail(
        self, yaml_content, required_fields, yaml_validator_mock
    ):
        """
        Test if validate_yaml_keys return False given that yaml content does not has required columns
        :param yaml_content: yaml as dict
        :param required_fields: keys to be validated
        :param yaml_validator_mock: mock of YamlValidator declared in conftest
        """
        assert (
            yaml_validator_mock.validate_yaml_keys(yaml_content, required_fields)
            is False
        )

    @pytest.mark.parametrize(
        "yaml_content", [{"a": ["b"], "b": ["c", "d"], "c": ["e"], "d": ["e"]}]
    )
    def test_list_dependencies(self, yaml_content, yaml_validator_mock):
        """
        Tests if validate_list_dependencies() returns True given that all DAG dependencies are
        represented as lists of strings

        :param yaml_content: yaml as dict
        :param yaml_validator_mock: mock of YamlValidator declared in conftest
        """
        assert yaml_validator_mock.validate_list_dependencies(yaml_content)

    @pytest.mark.parametrize(
        "yaml_content", [{"a": ["b"], "b": ["c", "d"], "c": [{"e": ["f"]}], "d": ["e"]}]
    )
    def test_list_dependencies_fail(self, yaml_content, yaml_validator_mock):
        """
        Tests if validate_list_dependencies() returns False given that one of the DAG dependencies
        is represented as a list of dicts

        :param yaml_content: yaml as dict
        :param yaml_validator_mock: mock of YamlValidator declared in conftest
        """
        assert yaml_validator_mock.validate_list_dependencies(yaml_content) is False

    @pytest.mark.parametrize(
        "yaml_content",
        [{"a": ["b"], "b": ["c", "d"], "c": ["e"], "d": ["c"], "x": ["y"]}],
    )
    def test_cyclic_dependencies(self, yaml_content, yaml_validator_mock):
        """
        Tests if validate_cyclic_dependency() returns True given that there are no dependency cycles.

        :param yaml_content: yaml as dict
        :param yaml_validator_mock: mock of YamlValidator declared in conftest
        """
        assert yaml_validator_mock.validate_cyclic_dependency(yaml_content)

    @pytest.mark.parametrize(
        "yaml_content",
        [{"a": ["b"], "b": ["c", "d"], "c": ["e"], "d": ["a"], "x": ["y"]}],
    )
    def test_cyclic_dependencies_fail(self, yaml_content, yaml_validator_mock):
        """
        Tests if validate_cyclic_dependency() returns False given that there is a dependency cycle (a, b, d, a).

        :param yaml_content: yaml as dict
        :param yaml_validator_mock: mock of YamlValidator declared in conftest
        """
        assert yaml_validator_mock.validate_cyclic_dependency(yaml_content) is False
