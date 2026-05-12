from unittest.mock import patch

import pytest

from bietlejuice.base.files_validation.validators.sql_validator import SQLValidator
from bietlejuice.base.files_validation.validators.yaml_validator import YamlValidator


@pytest.fixture
def sql_validator_mock():
    with patch.object(SQLValidator, "read_file"):
        mocked_validator = SQLValidator("mock_file_path")
    return mocked_validator


@pytest.fixture
def yaml_validator_mock():
    with patch.object(YamlValidator, "read_file"):
        mocked_validator = YamlValidator("mock_file_path")
    return mocked_validator
