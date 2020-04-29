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
                {"query", "funnel_side"}
            )
        ]
    )
    def test_yaml_keys_validator(self, yaml_content, required_fields, YamlValidatorMock):
        """
        Test if validate_yaml_keys return True given that yaml content has all required columns
        :param yaml_content: yaml as dict
        :param required_fields: keys to be validated
        :param YamlValidatorMock: mock of YamlValidator declared in conftest
        """
        assert YamlValidatorMock.validate_yaml_keys(yaml_content, required_fields)

    @pytest.mark.parametrize(
        "yaml_content, required_fields",
        [
            (
                {"rule_id": {"query": "path_to_query.sql", "funnel_side": "demand"}},
                {"query", "side"}
            )
        ]
    )
    def test_yaml_missing_key_fail(self, yaml_content, required_fields, YamlValidatorMock):
        """
        Test if validate_yaml_keys return False given that yaml content does not has required columns
        :param yaml_content: yaml as dict
        :param required_fields: keys to be validated
        :param YamlValidatorMock: mock of YamlValidator declared in conftest
        """
        assert YamlValidatorMock.validate_yaml_keys(yaml_content, required_fields) is False
