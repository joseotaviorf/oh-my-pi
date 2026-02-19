"""
Unit tests for utility functions.
"""

import pytest
import json
from unittest.mock import patch


class TestTimestampToDateString:
    """Tests for timestamp_to_date_string function."""

    def test_basic_conversion(self):
        """Test basic timestamp to date string conversion."""
        from bietlejuice.qube.jobs.common.utils import timestamp_to_date_string

        # 2025-06-29 00:00:00 UTC
        ts = 1751155200
        result = timestamp_to_date_string(ts)
        # Note: Result depends on local timezone
        assert len(result) == 10
        assert result.count("-") == 2

    def test_format(self):
        """Test output format is yyyy-MM-dd."""
        from bietlejuice.qube.jobs.common.utils import timestamp_to_date_string

        ts = 1609459200  # 2021-01-01 00:00:00 UTC
        result = timestamp_to_date_string(ts)

        # Should be parseable as date
        parts = result.split("-")
        assert len(parts) == 3
        assert len(parts[0]) == 4  # Year
        assert len(parts[1]) == 2  # Month
        assert len(parts[2]) == 2  # Day


class TestGetWindowRange:
    """Tests for get_window_range function."""

    def test_with_date_string(self):
        """Test window range with date string."""
        from bietlejuice.qube.jobs.common.utils import get_window_range

        lo, hi = get_window_range("2025-06-29", 7)

        # hi should be midnight of 2025-06-29
        # lo should be hi - 7 days
        assert hi > lo
        assert hi - lo == 7 * 86400

    def test_zero_window(self):
        """Test zero-day window."""
        from bietlejuice.qube.jobs.common.utils import get_window_range

        lo, hi = get_window_range("2025-06-29", 0)

        assert lo == hi

    def test_one_day_window(self):
        """Test one-day window."""
        from bietlejuice.qube.jobs.common.utils import get_window_range

        lo, hi = get_window_range("2025-06-29", 1)

        assert hi - lo == 86400

    def test_28_day_window(self):
        """Test 28-day window."""
        from bietlejuice.qube.jobs.common.utils import get_window_range

        lo, hi = get_window_range("2025-06-29", 28)

        assert hi - lo == 28 * 86400


class TestDefaultJson:
    """Tests for dimension value JSON wrapping."""

    def test_get_default_json_string(self):
        """Test default JSON for string type."""
        from bietlejuice.qube.jobs.common.utils import get_default_json
        import json

        result = get_default_json("single", "string", {"unknown_string": "UNKNOWN"})
        parsed = json.loads(result)

        assert "singleValued" in parsed
        assert parsed["singleValued"]["stringValue"] == "UNKNOWN"

    def test_get_default_json_number(self):
        """Test default JSON for number type."""
        from bietlejuice.qube.jobs.common.utils import get_default_json
        import json

        result = get_default_json("single", "number", {"unknown_number": 0.0})
        parsed = json.loads(result)

        assert "singleValued" in parsed
        assert parsed["singleValued"]["numberValue"] == 0.0

    def test_get_default_json_boolean(self):
        """Test default JSON for boolean type."""
        from bietlejuice.qube.jobs.common.utils import get_default_json
        import json

        result = get_default_json("single", "boolean", {"unknown_boolean": False})
        parsed = json.loads(result)

        assert "singleValued" in parsed
        assert parsed["singleValued"]["booleanValue"] is False

    def test_get_default_json_multi_string(self):
        """Test default JSON for multi-valued string."""
        from bietlejuice.qube.jobs.common.utils import get_default_json
        import json

        result = get_default_json("multi", "string", {})
        parsed = json.loads(result)

        assert "multiValued" in parsed
        # Multi-valued returns an empty array directly
        assert parsed["multiValued"] == []

    def test_get_default_json_no_defaults(self):
        """Test default JSON when no defaults provided."""
        from bietlejuice.qube.jobs.common.utils import get_default_json
        import json

        result = get_default_json("single", "string", None)
        parsed = json.loads(result)

        assert "singleValued" in parsed
        assert parsed["singleValued"]["stringValue"] == "UNKNOWN"


class TestSpecLoader:
    """Tests for spec loading functionality."""

    def test_load_valid_spec(self):
        """Test loading a valid spec from JSON."""
        from bietlejuice.qube.jobs.common.specs_loader import load_spec_from_json

        spec_json = json.dumps(
            {
                "entity": "visit",
                "name": "visit_business_context",
                "source": {"date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')"},
                "logic": {
                    "card": "single",
                    "type": "string",
                    "agg": "last",
                    "value_col": "business_context",
                },
            }
        )

        spec = load_spec_from_json(spec_json, validate=False)

        assert spec["entity"] == "visit"
        assert spec["name"] == "visit_business_context"

    def test_load_spec_with_validation(self):
        """Test loading a spec with Pydantic validation."""
        from bietlejuice.qube.jobs.common.specs_loader import load_spec_from_json

        spec_json = json.dumps(
            {
                "entity": "visit",
                "name": "visit_business_context",
                "source": {
                    "date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')",
                    "select": ["id_visit", "business_context"],
                },
                "logic": {
                    "card": "single",
                    "type": "string",
                    "agg": "last",
                    "value_col": "business_context",
                },
                "order_by": {"ts_col": "dt_visit", "nulls_last": True},
                "defaults": {"unknown_string": "UNKNOWN"},
                "windows": [1, 7, 28],
            }
        )

        spec = load_spec_from_json(spec_json, validate=True)

        assert spec["entity"] == "visit"
        assert "source" in spec
        assert "logic" in spec

    def test_load_nonexistent_spec(self):
        """Test loading non-existent spec raises error."""
        from bietlejuice.qube.jobs.common.specs_loader import load_spec

        with pytest.raises(FileNotFoundError):
            load_spec("nonexistent/path.yaml")

    def test_infer_spec_type_dimension(self):
        """Test spec type inference for dimension from path."""
        from bietlejuice.qube.jobs.common.specs_loader import _infer_spec_type

        spec = {
            "entity": "visit",
            "name": "status",
            "source": {},
            "logic": {"agg": "last"},
        }

        assert _infer_spec_type("/specs/dimensions/test.yaml", spec) == "dimension"

    def test_infer_spec_type_measure(self):
        """Test spec type inference for measure from path."""
        from bietlejuice.qube.jobs.common.specs_loader import _infer_spec_type

        spec = {
            "entity": "visit",
            "name": "unique",
            "source": {},
            "logic": {"filter_sql": "TRUE"},
        }

        assert _infer_spec_type("/specs/measures/test.yaml", spec) == "measure"

    def test_infer_spec_type_metric(self):
        """Test spec type inference for metric from content."""
        from bietlejuice.qube.jobs.common.specs_loader import _infer_spec_type

        spec = {
            "entity": "visit",
            "name": "test",
            "dimensions": [{"name": "d1"}],
            "measures": [{"name": "m1"}],
        }

        assert _infer_spec_type("/unknown/path.yaml", spec) == "metric"

    def test_infer_spec_type_measure_from_content(self):
        """Test spec type inference for measure from content."""
        from bietlejuice.qube.jobs.common.specs_loader import _infer_spec_type

        spec = {
            "entity": "visit",
            "name": "unique",
            "source": {},
            "logic": {"filter_sql": "TRUE"},
        }

        # Without a measures/dimensions path, infer from content
        assert _infer_spec_type("/unknown/path.yaml", spec) == "measure"

    def test_load_spec_validation_error(self):
        """Test that validation errors are raised properly."""
        from bietlejuice.qube.jobs.common.specs_loader import load_spec_from_json
        from pydantic import ValidationError

        # Create an invalid dimension spec JSON (negative window)
        invalid_spec_json = json.dumps(
            {
                "entity": "visit",
                "name": "test",
                "source": {
                    "date_expr": "unix_timestamp(dt_visit, 'yyyy-MM-dd')",
                    "select": ["id_visit", "status"],
                },
                "logic": {
                    "card": "single",
                    "type": "string",
                    "agg": "last",
                    "value_col": "status",
                },
                "windows": -1,  # Invalid: negative window
            }
        )

        with pytest.raises(ValidationError):
            load_spec_from_json(invalid_spec_json, validate=True)

    @patch("bietlejuice.qube.jobs.common.specs_loader.validate_spec_path")
    def test_load_spec_empty_file(self, mock_validate_path):
        """Test loading empty spec file raises error."""
        from bietlejuice.qube.jobs.common.specs_loader import load_spec
        from pathlib import Path
        import tempfile
        import os

        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
            f.write("")  # Empty file
            temp_path = f.name

        mock_validate_path.return_value = Path(temp_path)

        try:
            with pytest.raises(ValueError, match="Empty spec file"):
                load_spec(temp_path, validate=False)
        finally:
            os.unlink(temp_path)

    @patch("bietlejuice.qube.jobs.common.specs_loader.validate_spec_path")
    def test_load_spec_invalid_yaml(self, mock_validate_path):
        """Test loading invalid YAML raises error."""
        from bietlejuice.qube.jobs.common.specs_loader import load_spec
        from pathlib import Path
        import yaml
        import tempfile
        import os

        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
            f.write("invalid: yaml: content: [")  # Invalid YAML
            temp_path = f.name

        mock_validate_path.return_value = Path(temp_path)

        try:
            with pytest.raises(yaml.YAMLError):
                load_spec(temp_path, validate=False)
        finally:
            os.unlink(temp_path)
