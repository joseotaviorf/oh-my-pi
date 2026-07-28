from unittest import mock

import pytest

from bietlejuice.base.observability.profiling_config import (
    DEFAULT_ENABLED_KEY,
    KILL_SWITCH_KEY,
    ProfilingConfig,
)


class TestIsProfilingActive:
    @pytest.mark.parametrize(
        ("kill_switch", "default_enabled", "dag_enabled", "expected"),
        [
            # kill-switch off => nothing runs, regardless of opt-in
            (False, True, True, False),
            (False, False, None, False),
            # opted in explicitly
            (True, False, True, True),
            # opted out explicitly
            (True, True, False, False),
            # absent observability block => global default decides
            (True, False, None, False),  # Phase 1: default off
            (True, True, None, True),  # Phase 2: default on
        ],
    )
    def test_gate_matrix(self, kill_switch, default_enabled, dag_enabled, expected):
        # Arrange
        config = ProfilingConfig(
            kill_switch=kill_switch, default_enabled=default_enabled
        )

        # Act
        result = config.is_profiling_active(dag_enabled)

        # Assert
        assert result is expected


class TestFromConfigurationService:
    @pytest.mark.parametrize(
        ("raw_kill", "raw_default", "exp_kill", "exp_default"),
        [
            ("true", "false", True, False),
            (True, True, True, True),
            ("1", "yes", True, True),
            ("false", "no", False, False),
        ],
    )
    def test_reads_and_coerces_flags(
        self, raw_kill, raw_default, exp_kill, exp_default
    ):
        # Arrange
        service = mock.MagicMock()
        service.get_config.side_effect = lambda key: {
            KILL_SWITCH_KEY: raw_kill,
            DEFAULT_ENABLED_KEY: raw_default,
        }[key]

        # Act
        config = ProfilingConfig.from_configuration_service(service)

        # Assert
        assert config.kill_switch is exp_kill
        assert config.default_enabled is exp_default

    def test_missing_keys_fall_open_to_defaults(self):
        # Arrange
        service = mock.MagicMock()
        service.get_config.side_effect = KeyError("absent")

        # Act
        config = ProfilingConfig.from_configuration_service(service)

        # Assert — kill-switch defaults on, default_enabled defaults off (Phase 1)
        assert config.kill_switch is True
        assert config.default_enabled is False
