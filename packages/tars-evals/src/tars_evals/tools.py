"""Sandboxed read_file + run_bash tools mirroring the Claude Code/Cursor
contract tars's SKILL.md assumes.

run_bash is allowlisted to the three tars scripts (resolve_session.py,
datahub_connect.py, trino_connect.py) plus cat/ls, each of which must
resolve inside the tars skill directory (not just match by basename) —
never a raw shell. datahub_connect.py and trino_connect.py are intercepted
and answered in-process (no real Trino/OAuth); resolve_session.py runs for
real. The scorer only compares the SQL text tars *asked* to run against the
golden SQL, so mocking Trino output loses nothing (see scorer.py).
"""

import asyncio
import json
import re
import shlex
from pathlib import Path

from inspect_ai.tool import Tool, ToolError, tool

from tars_evals.datahub_mock import execute_datahub_gql

_ALLOWED_SCRIPTS = ("resolve_session.py", "datahub_connect.py", "trino_connect.py")

# Fail-fast clarity heuristic, NOT the security boundary: run_bash uses
# create_subprocess_exec (no shell), so these are inert literal bytes. `|`/`&`/
# `2>&1` are handled in normalize_command; newline, `<`/`>`, and `$` are
# intentionally allowed (multi-line SQL, comparisons, parameterized GraphQL).
_SHELL_METACHARACTERS = re.compile(r"[;`]")


_PAGERS = ("head", "tail")


# tars's documented `python3 -c "<body>"` DataHub discovery snippet, whose body
# imports datahub_connect (see is_datahub_dash_c).
_DATAHUB_C_IMPORT = re.compile(r"(?:from|import)\s+datahub_connect\b")


def is_datahub_dash_c(argv: list[str]) -> bool:
    """True when argv is `python3 -c <body>` and <body> imports datahub_connect
    — tars's documented discovery snippet, routed to the datahub interceptor
    rather than exec'd (see DATAHUB.md)."""
    return (
        len(argv) >= 3
        and argv[0] in ("python3", "python")
        and argv[1] == "-c"
        and bool(_DATAHUB_C_IMPORT.search(argv[2]))
    )


def normalize_command(command: str) -> tuple[list[str], str | None]:
    """Split `command` into argv, tolerating the shell idioms tars emits (a
    trailing `2>&1`/`2>/dev/null` redirect and a `| head`/`| tail` pager pipe)
    that the exec-based sandbox would otherwise choke on. Any other pipe or
    `||` chaining is rejected. Returns (argv, rejection_reason)."""
    try:
        tokens = shlex.split(command)
    except ValueError as e:
        return [], f"Could not parse command (invalid quoting): {e}"

    # shlex tokenizes `||` as one two-char token, so it slips past the `|`
    # check below — catch it first for an accurate rejection message.
    if "||" in tokens:
        return [], (
            "Command chaining with `||` is not permitted. "
            "Use separate tool calls instead."
        )

    if "|" in tokens:
        idx = tokens.index("|")
        rhs = tokens[idx + 1 : idx + 2]
        if rhs and rhs[0] in _PAGERS:
            tokens = tokens[:idx]
        else:
            return [], (
                "Pipe into a non-pager command is not permitted (only "
                "`| head`/`| tail` are tolerated; use separate tool calls)."
            )

    # Redirects are inert under exec; strip them so they don't become literal
    # argv elements. `2>/dev/null` shows up in agent-hallucinated probes.
    while tokens and tokens[-1] in ("2>&1", "2>/dev/null"):
        tokens = tokens[:-1]

    return tokens, None


def validate_sandbox_command(
    command: str, skill_dir: Path | None = None
) -> tuple[list[str] | None, str | None]:
    """Parse/normalize ``command`` once; return ``(argv, None)`` when allowed.

    When rejected, returns ``(None, rejection_reason)`` so callers can build
    actionable error messages without re-parsing the command string.
    """
    argv, reason = normalize_command(command)
    if reason is not None:
        return None, reason
    if not argv:
        return None, "Empty command."

    # The datahub `-c` body is arbitrary Python (routinely contains `;`) and is
    # routed to the interceptor, so it must bypass the metacharacter guard.
    if is_datahub_dash_c(argv):
        return argv, None

    match = _SHELL_METACHARACTERS.search(" ".join(argv))
    if match:
        return None, (
            f"Shell operator {match.group()!r} is not permitted (the sandbox "
            "runs via exec, not a shell — use separate tool calls instead of "
            "chaining)."
        )

    head = argv[0]

    if head in ("cat", "ls"):
        if skill_dir is None:
            return None, "No skill_dir configured — cat/ls are unavailable."
        path_args = [a for a in argv[1:] if not a.startswith("-")]
        if not path_args:
            return None, f"{head} requires a path inside the tars skill directory."
        outside = [p for p in path_args if not is_path_readable(p, skill_dir)]
        if outside:
            return None, (
                f"Path(s) outside the tars skill directory: {outside}. "
                "cat/ls are restricted to files inside the skill directory."
            )
        return argv, None

    if head in ("python3", "python"):
        if skill_dir is None:
            return None, "No skill_dir configured — python3 invocations are unavailable."
        if len(argv) < 2:
            return None, "python3 requires a script path argument."
        script_arg = argv[1]
        if Path(script_arg).name not in _ALLOWED_SCRIPTS:
            return None, (
                f"{Path(script_arg).name!r} is not on the allowlist. "
                f"Permitted scripts: {', '.join(_ALLOWED_SCRIPTS)}."
            )
        if not is_path_readable(script_arg, skill_dir):
            return None, (
                f"Script path {script_arg!r} is outside the tars skill directory. "
                "Use the exact path shown in the [Eval harness note] system message."
            )
        return argv, None

    return None, (
        f"{head!r} is not a permitted command. "
        f"Only python3 (for {', '.join(_ALLOWED_SCRIPTS)}), cat, and ls are allowed."
    )


def command_rejection_reason(command: str, skill_dir: Path | None = None) -> str | None:
    """Return a short human-readable reason why `command` is not allowed, or
    None if it is allowed. Callers use this to build actionable error messages
    rather than a single generic "not permitted" wall of text.
    """
    _, reason = validate_sandbox_command(command, skill_dir)
    return reason


def is_command_allowed(command: str, skill_dir: Path | None = None) -> bool:
    """True only for a recognised, side-effect-bounded invocation.

    Both cat/ls and the allowlisted python3 scripts require every path (incl.
    the script itself) to resolve inside `skill_dir` — matching a script name
    by basename alone would let `/tmp/evil/resolve_session.py` get exec'd.
    Fails closed when `skill_dir` is None.
    """
    return command_rejection_reason(command, skill_dir) is None


def _is_script_invocation(argv: list[str], script_name: str) -> bool:
    return (
        len(argv) >= 2
        and argv[0] in ("python3", "python")
        and Path(argv[1]).name == script_name
    )


def _is_trino_connect_invocation(args: list[str]) -> bool:
    return _is_script_invocation(args, "trino_connect.py")


def _json_line(payload: dict) -> str:
    return json.dumps(payload) + "\n"


def _mock_trino_connect_response(args: list[str]) -> str:
    """Canned trino_connect.py-shaped response, no real Trino/OAuth. The shape
    only needs to read as a successful call to tars; the scorer reads SQL from
    the tool-call args, not this output, so row content is placeholder."""
    if "--check-token" in args:
        return "trino_token_cache_valid: yes\n"
    if "--init-oauth" in args or "--complete-oauth" in args:
        return _json_line(
            {
                "status": "success",
                "message": "Mocked by the eval harness — no real OAuth flow occurs here.",
            }
        )
    if "--auth-only" in args:
        return _json_line(
            {
                "status": "success",
                "message": "OAuth2 token cached. (mocked)",
            }
        )
    # Plain --query (or anything else): one-row placeholder envelope, keyed
    # preview vs data to match the shape the real script would return.
    preview_only = "--preview-only" in args or "--csv-output" in args
    key = "preview" if preview_only else "data"
    return _json_line(
        {
            "status": "success",
            "columns": ["placeholder_column"],
            key: [["placeholder_value"]],
            "count": 1,
        }
    )


def _is_datahub_gql_invocation(argv: list[str]) -> bool:
    """True for tars's two DataHub shapes: a direct datahub_connect.py call or
    the `python3 -c "<body>"` snippet. Both are answered by _datahub_response."""
    return _is_script_invocation(argv, "datahub_connect.py") or is_datahub_dash_c(argv)


# Matches the first single/triple-quoted GraphQL string in a `gql(QUERY, VARS)`
# call inside a `python3 -c "<body>"` body; variables in the body aren't parsed.
_GQL_CALL_RE = re.compile(r"gql\(\s*(['\"]{1,3})(?P<q>.+?)\1", re.DOTALL)


def _extract_gql(argv: list[str]) -> tuple[str, dict | None] | str | None:
    """Return (query, variables) for a `gql` call, the literal 'probe'/'help'/
    'access' sentinel, or None if this datahub invocation carries no query.
    Skips --timeout/--env value pairs and flags."""
    if is_datahub_dash_c(argv):
        m = _GQL_CALL_RE.search(argv[2])
        return (m.group("q"), None) if m else None
    rest = argv[2:]  # after `python3 datahub_connect.py`
    if rest and rest[0] == "probe":
        return "probe"
    if rest and rest[0] == "access-instructions":
        return "access"
    if "--help" in rest or "-h" in rest:
        return "help"
    if not rest or rest[0] != "gql":
        return None
    rest = rest[1:]
    query, variables = None, None
    i = 0
    while i < len(rest):
        tok = rest[i]
        if tok == "--variables":
            if i + 1 < len(rest):
                variables = json.loads(rest[i + 1])
            i += 2
            continue
        if tok in ("--timeout", "--env"):
            i += 2
            continue
        if tok.startswith("-"):
            i += 1
            continue
        if query is None:
            query = tok
        i += 1
    return (query, variables) if query else None


def _datahub_response(argv: list[str]) -> str:
    """Answer a datahub_connect.py invocation from the local GraphQL backend
    without spawning a subprocess. Mirrors datahub_connect.py main(): the only
    subcommands are `gql`, `probe`, and `access-instructions` (no discover/
    hydrate in this skill version)."""
    extracted = _extract_gql(argv)
    if extracted == "probe":
        return _json_line({"status": "ok", "probe_ok": True})
    if extracted == "access":
        return _json_line(
            {"status": "ok", "message": "access instructions (mocked by eval harness)"}
        )
    if extracted == "help":
        return "usage: datahub_connect.py gql '<query>' [--variables JSON] [--timeout N]\n"
    if not extracted:
        return _json_line({"errors": [{"message": "no GraphQL query found"}]})
    query, variables = extracted
    return _json_line(execute_datahub_gql(query, variables))


def is_path_readable(path: str, skill_dir: Path) -> bool:
    """True when `path` resolves to `skill_dir` itself or a path inside it."""
    try:
        resolved = Path(path).resolve()
        resolved_skill_dir = skill_dir.resolve()
    except (OSError, RuntimeError):
        return False
    return resolved == resolved_skill_dir or resolved_skill_dir in resolved.parents


@tool
def run_bash(skill_dir: Path) -> Tool:
    async def execute(command: str) -> str:
        """Run a shell command.

        Only invocations of tars's resolve_session.py, datahub_connect.py, or
        trino_connect.py (via `python3 <path>/<script>.py ...`), plus `cat`/`ls`
        restricted to paths inside the tars skill directory, are permitted.
        Any other command is rejected.

        Args:
            command: The shell command to run.

        Returns:
            Combined stdout/stderr from the command.
        """
        args, reason = validate_sandbox_command(command, skill_dir)
        if reason is not None:
            raise ToolError(f"[Eval sandbox] {reason}")

        # exec (no shell): multi-line SQL passed as one argv element can't be
        # reinterpreted as control chars, so there is no injection surface.

        if _is_datahub_gql_invocation(args):
            return _datahub_response(args)

        if _is_trino_connect_invocation(args):
            return _mock_trino_connect_response(args)

        proc = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        try:
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=60)
        except asyncio.TimeoutError as e:
            # asyncio doesn't kill the child on timeout — reap it so it doesn't
            # linger as a zombie, then surface a normal tool failure.
            proc.kill()
            await proc.wait()
            raise ToolError(f"Command timed out after 60s: {command!r}") from e
        return stdout.decode(errors="replace")

    return execute


@tool
def read_file(skill_dir: Path) -> Tool:
    async def execute(path: str) -> str:
        """Read a file's contents.

        Only files inside the tars skill directory (SKILL.md and docs/*.md)
        may be read.

        Args:
            path: Absolute path to the file to read.

        Returns:
            The file's text contents.
        """
        if not is_path_readable(path, skill_dir):
            raise ToolError(
                f"Path not permitted by the eval harness sandbox: {path!r}. "
                "Only files inside the tars skill directory may be read."
            )
        try:
            return Path(path).read_text()
        except FileNotFoundError as e:
            raise ToolError(f"File not found: {path!r}") from e
        except IsADirectoryError as e:
            raise ToolError(f"Path is a directory, not a file: {path!r}") from e
        except (OSError, UnicodeDecodeError) as e:
            raise ToolError(f"Could not read {path!r}: {e}") from e

    return execute
