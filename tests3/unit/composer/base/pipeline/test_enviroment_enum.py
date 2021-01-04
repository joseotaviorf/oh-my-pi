import pytest

from bietlejuice.jobs.composer.base.pipeline import EnvironmentEnum


class TestEnvironmentEnum:
    @pytest.mark.parametrize(
        "env, expected_return",
        [
            (EnvironmentEnum.FORNO, True),
            (EnvironmentEnum.PROD, True),
            ("some wrong env", False),
        ],
    )
    def test_is_valid_environment(self, env, expected_return):
        # act
        returned_value = EnvironmentEnum.is_valid_environment(env)

        # assert
        assert returned_value == expected_return

    @pytest.mark.parametrize(
        "env, expected_return",
        [(EnvironmentEnum.FORNO, True), (EnvironmentEnum.PROD, True)],
    )
    def test_validate_env_with_valid_env(self, env, expected_return):
        # act
        returned_value = EnvironmentEnum.validate_env(env)

        # assert
        assert returned_value == expected_return

    def test_validate_env_with_invalid_env(self):
        # arrange
        env = "some wrong env"

        # assert
        with pytest.raises(RuntimeError):
            # act
            EnvironmentEnum.validate_env(env)
