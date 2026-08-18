"""The shared retry policy: bounded, not absent, and not unbounded."""

import pytest
from tars_evals import retry


def test_defaults_absorb_a_transient_blip():
    """max_retries=0 (the previous pin) turned one dropped TLS handshake into a
    failed sample and, at scale, into a bogus quality verdict."""
    assert retry.max_retries({}) == retry.DEFAULT_MAX_RETRIES
    assert retry.max_retries({}) > 0
    assert retry.request_timeout({}) == retry.DEFAULT_REQUEST_TIMEOUT
    assert retry.retry_on_error({}) == 0


def test_generate_config_kwargs_bounds_both_axes():
    kwargs = retry.generate_config_kwargs({})

    assert kwargs == {
        "max_retries": retry.DEFAULT_MAX_RETRIES,
        "timeout": retry.DEFAULT_REQUEST_TIMEOUT,
    }


def test_env_overrides_each_knob():
    env = {
        "TARS_EVAL_MAX_RETRIES": "3",
        "TARS_EVAL_REQUEST_TIMEOUT": "120",
        "TARS_EVAL_RETRY_ON_ERROR": "1",
    }

    assert retry.max_retries(env) == 3
    assert retry.request_timeout(env) == 120
    assert retry.retry_on_error(env) == 1


def test_zero_timeout_means_no_ceiling_not_instant_timeout():
    """A 0-second stop_after_delay would abort every request immediately."""
    assert retry.request_timeout({"TARS_EVAL_REQUEST_TIMEOUT": "0"}) is None
    assert "timeout" not in retry.generate_config_kwargs(
        {"TARS_EVAL_REQUEST_TIMEOUT": "0"}
    )


def test_zero_retries_remains_available_as_an_explicit_opt_in():
    assert retry.max_retries({"TARS_EVAL_MAX_RETRIES": "0"}) == 0


def test_blank_value_falls_back_to_the_default():
    assert retry.max_retries({"TARS_EVAL_MAX_RETRIES": "  "}) == retry.DEFAULT_MAX_RETRIES


@pytest.mark.parametrize("bad", ["-1", "abc", "3.5"])
def test_invalid_value_is_rejected_loudly(bad: str):
    with pytest.raises(ValueError, match="TARS_EVAL_MAX_RETRIES"):
        retry.max_retries({"TARS_EVAL_MAX_RETRIES": bad})
