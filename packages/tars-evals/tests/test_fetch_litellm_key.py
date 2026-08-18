"""fetch_litellm_key.sh must fail loudly, and must never echo the secret."""

import os
import subprocess
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parents[1] / "scripts" / "fetch_litellm_key.sh"
)


def _fake_qli(tmp_path: Path, body: str) -> dict[str, str]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    qli = bin_dir / "qli"
    qli.write_text("#!/usr/bin/env bash\n" + body)
    qli.chmod(0o755)
    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}{os.pathsep}{env['PATH']}"
    return env


def _run(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(SCRIPT)], capture_output=True, text=True, env=env, check=False
    )


def test_returns_the_bare_key_on_success(tmp_path: Path):
    env = _fake_qli(tmp_path, 'echo "key: sk-secret-value"\n')

    result = _run(env)

    assert result.returncode == 0
    assert result.stdout == "sk-secret-value"


def test_pins_the_vault_environment_instead_of_inheriting_qli_env_set(
    tmp_path: Path,
):
    """The secret path is hard-coded to apps/forno/…, so the Vault SERVER must
    be pinned too. Left to ambient `qli env set` state, anyone on prod got a
    bare 403 that reads like an expired login."""
    env = _fake_qli(
        tmp_path, 'printf "%s\\n" "$*" >"$ARGS_LOG"\necho "key: sk-secret-value"\n'
    )
    env["ARGS_LOG"] = str(tmp_path / "args.log")

    result = _run(env)

    assert result.returncode == 0
    assert "-e forno" in Path(env["ARGS_LOG"]).read_text()


def test_vault_environment_is_overridable(tmp_path: Path):
    env = _fake_qli(
        tmp_path, 'printf "%s\\n" "$*" >"$ARGS_LOG"\necho "key: sk-secret-value"\n'
    )
    env["ARGS_LOG"] = str(tmp_path / "args.log")
    env["TARS_LITELLM_VAULT_ENV"] = "prod"
    env["TARS_LITELLM_VAULT_PATH"] = "apps/shared/litellm/zordon-tars-llm"

    result = _run(env)

    assert result.returncode == 0
    args = Path(env["ARGS_LOG"]).read_text()
    assert "-e prod" in args
    assert "apps/shared/litellm/zordon-tars-llm" in args


def test_an_expired_session_fails_with_a_diagnosis_not_silence(tmp_path: Path):
    """`set -e` + pipefail + `2>/dev/null` used to abort this script before it
    could print anything, taking the whole eval queue down with a bare exit 1."""
    env = _fake_qli(tmp_path, 'echo "Code: 403. permission denied" >&2\nexit 1\n')

    result = _run(env)

    assert result.returncode == 1
    assert "403" in result.stderr
    assert "qli login" in result.stderr
    assert result.stdout == ""


def test_qli_stdout_is_never_echoed_on_the_error_path(tmp_path: Path):
    """Only qli's stderr is surfaced — its stdout is where the secret lives."""
    env = _fake_qli(
        tmp_path, 'echo "key: sk-secret-value"\necho "boom" >&2\nexit 1\n'
    )

    result = _run(env)

    assert result.returncode == 1
    assert "sk-secret-value" not in result.stderr
    assert "sk-secret-value" not in result.stdout
    assert "boom" in result.stderr


def test_a_secret_without_a_key_field_is_reported(tmp_path: Path):
    env = _fake_qli(tmp_path, 'echo "other_field: value"\n')

    result = _run(env)

    assert result.returncode == 1
    assert "no 'key' field" in result.stderr
