import pytest
from tests3.files_validation.validators.yaml_validator import YamlValidator
from tests3.files_validation.validators.sql_validator import SQLValidator
import os

ROOT_QUERY_PATH = "bietlejuice/db/dw/queries/marketing/costs/"


class TestMarketingRules:
    @pytest.mark.parametrize(
        "file_path, required_keys",
        [("bietlejuice/jobs/dags/marketing/costs/sharing_rules.yml", {"query", "funnel_side"})]
    )
    def test_share_rules_yaml(self, file_path, required_keys):
        validator = YamlValidator(file_path, validator_args=required_keys)
        result = validator.run_validator(validation_method=validator.validate_yaml_keys)
        assert result, "Yaml content must contains required fields"

    @pytest.mark.parametrize("file_path", os.listdir(ROOT_QUERY_PATH))
    def test_sql_sharing_costs_columns(self, file_path):
        validator = SQLValidator(
            ROOT_QUERY_PATH + file_path,
            validator_args=["sk_date", "city_group", "share"],
        )
        result = validator.run_validator(
            validation_method=validator.validate_sql_columns
        )
        assert result, "Query content must contains required columns at last select statement"
