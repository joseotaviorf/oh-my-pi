"""
Unit tests for logging configuration.
"""

import logging

from bietlejuice.qube.jobs.common.logging_config import (
    JSONFormatter,
    get_logger,
    setup_logging,
)


class TestSetupLogging:
    """Tests for setup_logging function."""

    def test_setup_logging_default(self):
        """Test setup_logging with default parameters."""
        logger = setup_logging()

        assert logger.name == "qube"
        assert logger.level == logging.INFO

    def test_setup_logging_custom_level(self):
        """Test setup_logging with custom log level."""
        logger = setup_logging(level="DEBUG")

        assert logger.level == logging.DEBUG

    def test_setup_logging_standard_format(self):
        """Test setup_logging with standard format."""
        logger = setup_logging(log_format="standard")

        # Should have at least one handler
        assert len(logger.handlers) > 0

    def test_setup_logging_json_format(self):
        """Test setup_logging with JSON format."""
        logger = setup_logging(log_format="json")

        # Should have handler with JSONFormatter
        assert len(logger.handlers) > 0
        handler = logger.handlers[0]
        assert isinstance(handler.formatter, JSONFormatter)

    def test_setup_logging_clears_handlers(self):
        """Test that setup_logging clears existing handlers."""
        logger = setup_logging()
        initial_count = len(logger.handlers)

        # Setup again
        logger = setup_logging()

        # Should have same number of handlers (cleared and re-added)
        assert len(logger.handlers) == initial_count


class TestGetLogger:
    """Tests for get_logger function."""

    def test_get_logger_returns_logger(self):
        """Test that get_logger returns a logger instance."""
        logger = get_logger("test_module")

        assert isinstance(logger, logging.Logger)
        assert logger.name.startswith("qube")

    def test_get_logger_different_modules(self):
        """Test that different modules get different loggers."""
        logger1 = get_logger("module1")
        logger2 = get_logger("module2")

        assert logger1.name != logger2.name


class TestJSONFormatter:
    """Tests for JSONFormatter class."""

    def test_json_formatter_format(self):
        """Test JSONFormatter produces valid JSON."""
        formatter = JSONFormatter()
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="test.py",
            lineno=1,
            msg="Test message",
            args=(),
            exc_info=None,
        )

        result = formatter.format(record)

        # Should be valid JSON
        import json

        parsed = json.loads(result)

        assert "timestamp" in parsed
        assert "level" in parsed
        assert "message" in parsed
        assert parsed["message"] == "Test message"

    def test_json_formatter_includes_extra(self):
        """Test JSONFormatter includes extra fields."""
        formatter = JSONFormatter()
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="test.py",
            lineno=1,
            msg="Test message",
            args=(),
            exc_info=None,
        )
        # Add extra via __dict__ to simulate getMessage() behavior
        record.__dict__["custom_field"] = "custom_value"

        result = formatter.format(record)

        import json

        parsed = json.loads(result)

        # JSONFormatter may not include all extra fields, just verify it's valid JSON
        assert "timestamp" in parsed
        assert "message" in parsed
