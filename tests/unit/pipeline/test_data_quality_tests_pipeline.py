import pytest
from unittest.mock import patch, MagicMock
import inspect


class TestCompatibilityFunction:
    """Tests for the _create_compatible_config_reader function"""

    @pytest.fixture
    def mock_config_reader_230(self):
        """Mock ConfigReader for version 2.3.0 (file-based only)"""

        class MockConfigReader230:
            def __init__(self, config_file_path):
                self.config_file_path = config_file_path

            def read(self):
                return {
                    "table_name": "test_table",
                    "table_level_validations": {
                        "has_size": {"greater_than": 1, "severity_level": "Warning"}
                    },
                }

        return MockConfigReader230

    @pytest.fixture
    def mock_config_reader_4101(self):
        """Mock ConfigReader for version 4.10.1+ (with content parameter)"""

        class MockConfigReader4101:
            def __init__(self, config_file_path=None, content=None):
                if content:
                    self.content = content
                elif config_file_path:
                    with open(config_file_path, "r") as f:
                        self.content = f.read()
                else:
                    raise ValueError(
                        "Either config_file_path or content must be provided"
                    )

            def read(self):
                return {
                    "table_name": "test_table",
                    "table_level_validations": {
                        "has_size": {"greater_than": 1, "severity_level": "Warning"}
                    },
                }

        return MockConfigReader4101

    def test_compatibility_function_can_be_imported(self):
        """Test that we can import the compatibility function"""
        # Mock all inmetro dependencies
        with patch.dict(
            "sys.modules",
            {
                "inmetro": MagicMock(),
                "inmetro.builders": MagicMock(),
                "inmetro.builders.validations": MagicMock(),
                "inmetro.builders.validations.pydeequ": MagicMock(),
                "inmetro.builders.validations.pydeequ.validation_suite_builder": MagicMock(),
                "inmetro.clients": MagicMock(),
                "inmetro.config_reader": MagicMock(),
                "inmetro.loaders": MagicMock(),
                "inmetro.validators": MagicMock(),
            },
        ):
            from bietlejuice.pipeline.data_quality_tests_pipeline import (
                _create_compatible_config_reader,
            )

            assert callable(_create_compatible_config_reader)

    def test_create_compatible_config_reader_with_content_parameter(
        self, mock_config_reader_4101
    ):
        """Test compatibility function with inmetro 4.10.1+ (content parameter exists)"""
        validation_content = """
table_name: test_table
table_level_validations:
  has_size:
    greater_than: 1
    severity_level: Warning
"""

        # Mock all inmetro dependencies and import the function
        with patch.dict(
            "sys.modules",
            {
                "inmetro": MagicMock(),
                "inmetro.builders": MagicMock(),
                "inmetro.builders.validations": MagicMock(),
                "inmetro.builders.validations.pydeequ": MagicMock(),
                "inmetro.builders.validations.pydeequ.validation_suite_builder": MagicMock(),
                "inmetro.clients": MagicMock(),
                "inmetro.config_reader": MagicMock(),
                "inmetro.loaders": MagicMock(),
                "inmetro.validators": MagicMock(),
            },
        ):
            from bietlejuice.pipeline.data_quality_tests_pipeline import (
                _create_compatible_config_reader,
            )

            with patch(
                "bietlejuice.pipeline.data_quality_tests_pipeline.ConfigReader",
                mock_config_reader_4101,
            ):
                config_reader = _create_compatible_config_reader(validation_content)
                result = config_reader.read()

            assert result["table_name"] == "test_table"
            assert "table_level_validations" in result
            assert result["table_level_validations"]["has_size"]["greater_than"] == 1

    def test_create_compatible_config_reader_without_content_parameter(
        self, mock_config_reader_230
    ):
        """Test compatibility function with inmetro 2.3.0 (no content parameter)"""
        validation_content = """
table_name: test_table
table_level_validations:
  has_size:
    greater_than: 1
    severity_level: Warning
"""

        # Mock all inmetro dependencies and import the function
        with patch.dict(
            "sys.modules",
            {
                "inmetro": MagicMock(),
                "inmetro.builders": MagicMock(),
                "inmetro.builders.validations": MagicMock(),
                "inmetro.builders.validations.pydeequ": MagicMock(),
                "inmetro.builders.validations.pydeequ.validation_suite_builder": MagicMock(),
                "inmetro.clients": MagicMock(),
                "inmetro.config_reader": MagicMock(),
                "inmetro.loaders": MagicMock(),
                "inmetro.validators": MagicMock(),
            },
        ):
            from bietlejuice.pipeline.data_quality_tests_pipeline import (
                _create_compatible_config_reader,
            )

            with patch(
                "bietlejuice.pipeline.data_quality_tests_pipeline.ConfigReader",
                mock_config_reader_230,
            ):
                config_reader = _create_compatible_config_reader(validation_content)
                result = config_reader.read()

            assert result["table_name"] == "test_table"
            assert "table_level_validations" in result
            assert result["table_level_validations"]["has_size"]["greater_than"] == 1

    def test_create_compatible_config_reader_logs_version_detection(
        self, mock_config_reader_4101
    ):
        """Test that the compatibility function logs which version is being used"""
        validation_content = "table_name: test_table"

        # Mock all inmetro dependencies
        with patch.dict(
            "sys.modules",
            {
                "inmetro": MagicMock(),
                "inmetro.builders": MagicMock(),
                "inmetro.builders.validations": MagicMock(),
                "inmetro.builders.validations.pydeequ": MagicMock(),
                "inmetro.builders.validations.pydeequ.validation_suite_builder": MagicMock(),
                "inmetro.clients": MagicMock(),
                "inmetro.config_reader": MagicMock(),
                "inmetro.loaders": MagicMock(),
                "inmetro.validators": MagicMock(),
            },
        ):
            from bietlejuice.pipeline.data_quality_tests_pipeline import (
                _create_compatible_config_reader,
            )

            with patch(
                "bietlejuice.pipeline.data_quality_tests_pipeline.ConfigReader",
                mock_config_reader_4101,
            ):
                with patch(
                    "bietlejuice.pipeline.data_quality_tests_pipeline.logger"
                ) as mock_logger:
                    _create_compatible_config_reader(validation_content)

                mock_logger.info.assert_called_with(
                    "Using inmetro 4.10.1+ ConfigReader with content parameter"
                )

    def test_create_compatible_config_reader_logs_fallback_version(
        self, mock_config_reader_230
    ):
        """Test that the compatibility function logs when using 2.3.0 version"""
        validation_content = "table_name: test_table"

        # Mock all inmetro dependencies
        with patch.dict(
            "sys.modules",
            {
                "inmetro": MagicMock(),
                "inmetro.builders": MagicMock(),
                "inmetro.builders.validations": MagicMock(),
                "inmetro.builders.validations.pydeequ": MagicMock(),
                "inmetro.builders.validations.pydeequ.validation_suite_builder": MagicMock(),
                "inmetro.clients": MagicMock(),
                "inmetro.config_reader": MagicMock(),
                "inmetro.loaders": MagicMock(),
                "inmetro.validators": MagicMock(),
            },
        ):
            from bietlejuice.pipeline.data_quality_tests_pipeline import (
                _create_compatible_config_reader,
            )

            with patch(
                "bietlejuice.pipeline.data_quality_tests_pipeline.ConfigReader",
                mock_config_reader_230,
            ):
                with patch(
                    "bietlejuice.pipeline.data_quality_tests_pipeline.logger"
                ) as mock_logger:
                    _create_compatible_config_reader(validation_content)

                mock_logger.info.assert_called_with(
                    "Using inmetro 2.3.0 ConfigReader - saving content to temporary file"
                )


class TestCompatibilityIntegration:
    """Integration tests for the compatibility feature"""

    def test_real_signature_inspection_content_parameter_exists(self):
        """Test signature inspection with a real class that has content parameter"""

        class RealConfigReaderNew:
            def __init__(self, config_file_path=None, content=None):
                pass

        signature = inspect.signature(RealConfigReaderNew.__init__)
        assert "content" in signature.parameters

    def test_real_signature_inspection_content_parameter_missing(self):
        """Test signature inspection with a real class that doesn't have content parameter"""

        class RealConfigReaderOld:
            def __init__(self, config_file_path):
                pass

        signature = inspect.signature(RealConfigReaderOld.__init__)
        assert "content" not in signature.parameters
