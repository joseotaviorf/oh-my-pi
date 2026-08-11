import asyncio
import json
from pathlib import Path

from inspect_ai.tool import ToolError
from tars_evals.tools import (
    is_command_allowed,
    is_path_readable,
    read_file,
    run_bash,
)


def test_allows_trino_connect_invocation(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    cmd = f"python3 {skill_dir / 'scripts' / 'trino_connect.py'} --check-token"
    assert is_command_allowed(cmd, skill_dir) is True


def test_allows_datahub_connect_invocation(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    cmd = f"python3 {skill_dir / 'scripts' / 'datahub_connect.py'} probe"
    assert is_command_allowed(cmd, skill_dir) is True


def test_allows_resolve_session_invocation(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    cmd = f"python3 {skill_dir / 'scripts' / 'resolve_session.py'} --user-slug jane.doe"
    assert is_command_allowed(cmd, skill_dir) is True


def test_rejects_python_script_outside_skill_dir(tmp_path: Path):
    # Basename matching one of the allowlisted script names is not enough —
    # the script itself must resolve inside skill_dir, otherwise a
    # same-named script planted anywhere else on disk would be
    # indistinguishable from the real one.
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    outside = tmp_path / "evil" / "trino_connect.py"
    assert is_command_allowed(f"python3 {outside} --check-token", skill_dir) is False


def test_rejects_python_script_without_skill_dir():
    assert (
        is_command_allowed("python3 /some/dir/trino_connect.py --check-token") is False
    )


def test_allows_cat_and_ls(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    (skill_dir / "docs").mkdir(parents=True)
    (skill_dir / "docs" / "TRINO.md").write_text("# Trino")
    assert (
        is_command_allowed(f"cat {skill_dir / 'docs' / 'TRINO.md'}", skill_dir) is True
    )
    assert is_command_allowed(f"ls -la {skill_dir / 'docs'}", skill_dir) is True


def test_rejects_cat_and_ls_outside_skill_dir(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    outside = tmp_path / "secrets.txt"
    outside.write_text("nope")
    assert is_command_allowed(f"cat {outside}", skill_dir) is False
    assert is_command_allowed(f"ls {tmp_path}", skill_dir) is False


def test_rejects_cat_and_ls_without_skill_dir():
    assert is_command_allowed("cat /some/dir/docs/TRINO.md") is False
    assert is_command_allowed("ls -la /some/dir/scripts") is False


def test_rejects_cat_and_ls_without_path_operands(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()

    for command in ("cat", "cat -n", "ls", "ls -la"):
        assert is_command_allowed(command, skill_dir) is False


def test_rejects_arbitrary_python_script():
    assert is_command_allowed("python3 /tmp/evil.py") is False


def test_rejects_shell_injection_via_chaining(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "scripts" / "trino_connect.py"
    assert (
        is_command_allowed(f"python3 {script} --check-token; rm -rf /", skill_dir)
        is False
    )


def test_rejects_pipe_chaining(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "scripts" / "trino_connect.py"
    assert is_command_allowed(f"cat /etc/passwd | python3 {script}", skill_dir) is False


def test_rejects_unrelated_command():
    assert is_command_allowed("curl https://example.com") is False


def test_allows_multiline_query_argument(tmp_path: Path):
    # Real golden SQL is multi-line; embedded newlines inside a quoted
    # --query argument must not be rejected (run_bash executes via exec,
    # not a shell, so they can never act as statement separators).
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "scripts" / "trino_connect.py"
    cmd = f'python3 {script} --query "SELECT 1\nFROM foo\nWHERE bar = 1"'
    assert is_command_allowed(cmd, skill_dir) is True


def test_allows_sql_comparison_operators(tmp_path: Path):
    # `<`/`>`/`>=`/`<=` are ubiquitous in real date/numeric SQL filters and
    # must be allowed (run_bash executes via exec, not a shell, so they can
    # never be reinterpreted as redirection).
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "scripts" / "trino_connect.py"
    cmd = (
        f"python3 {script} --query "
        '"SELECT 1 WHERE ts >= CAST(current_date AS TIMESTAMP) AND x < 5"'
    )
    assert is_command_allowed(cmd, skill_dir) is True


def test_allows_parameterized_graphql_with_dollar_variables(tmp_path: Path):
    # tars's documented DataHub discovery uses parameterized GraphQL, whose
    # variable syntax (`$q`, `$types`) and `--variables` payload contain '$'.
    # These must be allowed — '$' is inert under exec (no shell), and
    # blocking it broke tars's real discovery flow.
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "scripts" / "datahub_connect.py"
    cmd = (
        f"python3 {script} gql "
        "'query($q:String!,$types:[EntityType!]){searchAcrossEntities("
        "input:{query:$q,types:$types}){total}}' "
        '--variables \'{"q":"termination","types":["DATA_PRODUCT"]}\''
    )
    assert is_command_allowed(cmd, skill_dir) is True


def test_allows_skill_md(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text("---\nname: tars\n---\n")
    assert is_path_readable(str(skill_dir / "SKILL.md"), skill_dir) is True


def test_allows_skill_dir_itself(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    assert is_path_readable(str(skill_dir), skill_dir) is True


def test_allows_docs_subdirectory(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    (skill_dir / "docs").mkdir(parents=True)
    (skill_dir / "docs" / "TRINO.md").write_text("# Trino")
    assert is_path_readable(str(skill_dir / "docs" / "TRINO.md"), skill_dir) is True


def test_rejects_path_outside_skill_dir(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    outside = tmp_path / "secrets.txt"
    outside.write_text("nope")
    assert is_path_readable(str(outside), skill_dir) is False


def test_rejects_path_traversal(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    traversal = str(skill_dir / "docs" / ".." / ".." / "secrets.txt")
    assert is_path_readable(traversal, skill_dir) is False


def test_run_bash_tool_executes_allowed_command_async(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text("---\nname: tars\n---\n")

    async def _run() -> str:
        tool_fn = run_bash(skill_dir)
        return await tool_fn(command=f"cat {skill_dir / 'SKILL.md'}")

    result = asyncio.run(_run())
    assert isinstance(result, str)


def test_run_bash_tool_preserves_multiline_argument_verbatim(tmp_path: Path):
    # A stand-in "resolve_session.py" that just echoes its first argv back,
    # to prove the multi-line string arrives as ONE intact argv element
    # (i.e. run_bash uses exec, not a shell that would reinterpret it).
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "resolve_session.py"
    script.write_text("import sys; print(sys.argv[1])")
    multiline_sql = "SELECT 1\nFROM foo\nWHERE bar = 1"

    async def _run() -> str:
        tool_fn = run_bash(skill_dir)
        return await tool_fn(command=f'python3 {script} "{multiline_sql}"')

    result = asyncio.run(_run())
    assert result.strip() == multiline_sql


def test_run_bash_tool_does_not_execute_embedded_shell_metacharacters(tmp_path: Path):
    # Even if a shell metacharacter sneaks inside a quoted argument to an
    # allowed script, exec-based invocation must never treat it as a
    # statement separator / spawn a second process.
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "resolve_session.py"
    script.write_text("import sys; print(sys.argv[1])")
    canary = tmp_path / "should_not_exist"
    payload = f"harmless\ntouch {canary}"

    async def _run() -> str:
        tool_fn = run_bash(skill_dir)
        return await tool_fn(command=f'python3 {script} "{payload}"')

    result = asyncio.run(_run())
    assert result.strip() == payload
    assert not canary.exists()


def test_run_bash_tool_rejects_disallowed_command_async(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()

    async def _run() -> bool:
        tool_fn = run_bash(skill_dir)
        try:
            await tool_fn(command="curl https://example.com")
            return False
        except ToolError:
            return True

    assert asyncio.run(_run()) is True


def test_read_file_tool_reads_allowed_file_async(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text("---\nname: tars\n---\n")

    async def _run() -> str:
        tool_fn = read_file(skill_dir)
        return await tool_fn(path=str(skill_dir / "SKILL.md"))

    result = asyncio.run(_run())
    assert result == "---\nname: tars\n---\n"


def test_run_bash_mocks_trino_check_token_without_real_execution(tmp_path: Path):
    # The script path doesn't even need to exist: a real subprocess is
    # never spawned for trino_connect.py invocations.
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "scripts" / "trino_connect.py"

    async def _run() -> str:
        tool_fn = run_bash(skill_dir)
        return await tool_fn(command=f"python3 {script} --check-token")

    result = asyncio.run(_run())
    assert result.strip() == "trino_token_cache_valid: yes"


def test_run_bash_mocks_trino_query_with_success_envelope(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "scripts" / "trino_connect.py"

    async def _run() -> str:
        tool_fn = run_bash(skill_dir)
        return await tool_fn(command=f'python3 {script} --query "SELECT 1"')

    result = asyncio.run(_run())
    payload = json.loads(result)
    assert payload["status"] == "success"
    assert "data" in payload


def test_run_bash_mocks_trino_query_preview_shape(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "scripts" / "trino_connect.py"

    async def _run() -> str:
        tool_fn = run_bash(skill_dir)
        return await tool_fn(
            command=f'python3 {script} --query "SELECT 1" --preview-only'
        )

    result = asyncio.run(_run())
    payload = json.loads(result)
    assert payload["status"] == "success"
    assert "preview" in payload
    assert "data" not in payload


def test_read_file_tool_rejects_directory_path_async(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    (skill_dir / "docs").mkdir(parents=True)

    async def _run() -> bool:
        tool_fn = read_file(skill_dir)
        try:
            await tool_fn(path=str(skill_dir / "docs"))
            return False
        except ToolError:
            return True

    assert asyncio.run(_run()) is True


def test_run_bash_tool_kills_and_reaps_process_on_timeout(tmp_path: Path, monkeypatch):
    # A real 60s sleep would make this test unbearably slow; shrink the
    # timeout instead of the sleep duration so we exercise the actual
    # wait_for/kill/wait code path.
    import tars_evals.tools as tools_module

    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    script = skill_dir / "resolve_session.py"
    script.write_text("import time; time.sleep(5)")
    real_wait_for = asyncio.wait_for

    async def _short_timeout_wait_for(coro, timeout):
        return await real_wait_for(coro, timeout=0.05)

    monkeypatch.setattr(tools_module.asyncio, "wait_for", _short_timeout_wait_for)

    async def _run() -> bool:
        tool_fn = run_bash(skill_dir)
        try:
            await tool_fn(command=f"python3 {script}")
            return False
        except ToolError:
            return True

    assert asyncio.run(_run()) is True


def test_read_file_tool_rejects_disallowed_path_async(tmp_path: Path):
    skill_dir = tmp_path / "tars"
    skill_dir.mkdir()
    outside = tmp_path / "secrets.txt"
    outside.write_text("nope")

    async def _run() -> bool:
        tool_fn = read_file(skill_dir)
        try:
            await tool_fn(path=str(outside))
            return False
        except ToolError:
            return True

    assert asyncio.run(_run()) is True
