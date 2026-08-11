from tars_evals.tools import (
    command_rejection_reason,
    is_datahub_dash_c,
    normalize_command,
    validate_sandbox_command,
)


def test_validate_sandbox_command_returns_normalized_argv(tmp_path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "scripts" / "datahub_connect.py"
    cmd = f"python3 {script} probe 2>&1"
    argv, reason = validate_sandbox_command(cmd, skill_dir)
    assert reason is None
    assert argv == ["python3", str(script), "probe"]


def test_strips_trailing_redirect():
    argv, reason = normalize_command('python3 x/datahub_connect.py gql "{a}" 2>&1')
    assert reason is None
    assert argv == ["python3", "x/datahub_connect.py", "gql", "{a}"]


def test_strips_pipe_to_head():
    argv, reason = normalize_command('python3 x/datahub_connect.py gql "{a}" | head -5')
    assert reason is None
    assert argv == ["python3", "x/datahub_connect.py", "gql", "{a}"]


def test_strips_pipe_to_tail_and_redirect_together():
    argv, reason = normalize_command("cat x/SKILL.md 2>&1 | tail -20")
    assert reason is None
    assert argv == ["cat", "x/SKILL.md"]


def test_rejects_pipe_to_non_pager():
    argv, reason = normalize_command("cat /etc/passwd | python3 x/trino_connect.py")
    assert argv == []
    assert reason is not None
    assert "pipe" in reason.lower()


def test_plain_command_unchanged():
    argv, reason = normalize_command("python3 x/datahub_connect.py probe")
    assert reason is None
    assert argv == ["python3", "x/datahub_connect.py", "probe"]


def test_allows_python_dash_c_importing_datahub(tmp_path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    body = "import sys; sys.path.insert(0,'x'); from datahub_connect import gql; print(gql('{a}',{}))"
    cmd = f'python3 -c "{body}"'
    assert command_rejection_reason(cmd, skill_dir) is None
    assert is_datahub_dash_c(["python3", "-c", body]) is True


def test_rejects_python_dash_c_arbitrary(tmp_path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    cmd = "python3 -c \"import os; os.system('echo hi')\""
    assert command_rejection_reason(cmd, skill_dir) is not None
    assert is_datahub_dash_c(["python3", "-c", "import os"]) is False


def test_trailing_redirect_on_allowlisted_script_ok(tmp_path):
    # is_path_readable is a path-containment check (resolve() vs skill_dir
    # parents), NOT a disk-existence check, so the script need not exist.
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "scripts" / "datahub_connect.py"
    cmd = f"python3 {script} probe 2>&1"
    assert command_rejection_reason(cmd, skill_dir) is None


def test_rejects_logical_or_chaining():
    # `||` is tokenized as a single two-char token by shlex — distinct from
    # `|` — and must be caught before the single-pipe pager check.
    argv, reason = normalize_command(
        'python3 -c "import requests" 2>/dev/null || pip install requests'
    )
    assert argv == []
    assert reason is not None
    assert "||" in reason


def test_strips_2_dev_null_redirect():
    # Agents sometimes append `2>/dev/null` (not just `2>&1`) to silence
    # stderr. Both are inert under exec and should be stripped so they don't
    # become confusing literal argv elements passed to the Python script.
    argv, reason = normalize_command(
        "python3 x/datahub_connect.py probe 2>/dev/null"
    )
    assert reason is None
    assert argv == ["python3", "x/datahub_connect.py", "probe"]


def test_strips_both_redirects_when_stacked():
    # e.g. `cmd 2>/dev/null 2>&1` — strip innermost first, then outermost.
    argv, reason = normalize_command(
        "python3 x/trino_connect.py --check-token 2>/dev/null 2>&1"
    )
    assert reason is None
    assert argv == ["python3", "x/trino_connect.py", "--check-token"]
