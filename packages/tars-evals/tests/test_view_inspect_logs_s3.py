"""Unit tests for the S3 Inspect View launcher (QLI auth + command contract)."""

from __future__ import annotations

import importlib.util
import os
import subprocess
from pathlib import Path
from typing import Any

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "view_inspect_logs_s3.py"
UPLOAD_SCRIPT = (
    Path(__file__).resolve().parents[1] / "scripts" / "upload_inspect_logs_s3.py"
)


@pytest.fixture(scope="module")
def view_mod():
    spec = importlib.util.spec_from_file_location("view_inspect_logs_s3", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def upload_mod():
    spec = importlib.util.spec_from_file_location(
        "upload_inspect_logs_s3", UPLOAD_SCRIPT
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_default_log_dir(view_mod):
    assert view_mod.default_log_dir() == "s3://5a-tars-prod-data/evals/inspect"


def test_validate_s3_uri_accepts_and_strips_trailing_slash(view_mod):
    uri = view_mod.validate_s3_uri(
        "s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-1/pipeline-2/"
    )
    assert uri == (
        "s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-1/pipeline-2"
    )


@pytest.mark.parametrize(
    "bad_uri",
    [
        "",
        "logs/per_dataset",
        "https://example.com/logs",
        "s3://",
        "file:///tmp/logs",
        "s3://5a-tars-prod-data/evals/inspect;rm -rf /",
        "s3://5a-tars-prod-data/$(whoami)",
        "s3://5a-tars-prod-data/evals inspect",
    ],
)
def test_validate_s3_uri_rejects_non_s3(view_mod, bad_uri: str):
    with pytest.raises(view_mod.ViewConfigError):
        view_mod.validate_s3_uri(bad_uri)


def test_validate_role_arn(view_mod):
    assert view_mod.validate_role_arn("") is None
    assert (
        view_mod.validate_role_arn("arn:aws:iam::123456789012:role/sso_Example")
        == "arn:aws:iam::123456789012:role/sso_Example"
    )
    with pytest.raises(view_mod.ViewConfigError):
        view_mod.validate_role_arn("not-an-arn")
    with pytest.raises(view_mod.ViewConfigError):
        view_mod.validate_role_arn("arn:aws:iam::123:role/bad;injection")


def test_validate_port_bounds(view_mod):
    assert view_mod.validate_port(7575) == 7575
    with pytest.raises(view_mod.ViewConfigError):
        view_mod.validate_port(0)
    with pytest.raises(view_mod.ViewConfigError):
        view_mod.validate_port(70000)


def test_parse_qli_export_output_extracts_allowlisted_keys(view_mod):
    stdout = "\n".join(
        [
            "# comment from qli",
            "export AWS_ACCESS_KEY_ID=AKIATEST",
            "export AWS_SECRET_ACCESS_KEY='secret/with=equals'",
            'export AWS_SESSION_TOKEN="token-value"',
            "export AWS_DEFAULT_REGION=us-east-1",
            "export PATH=/should/not/be/kept",
            "export AWS_UNKNOWN_CUSTOM=nope",
            "echo noise",
        ]
    )
    creds = view_mod.parse_qli_export_output(stdout)
    assert creds == {
        "AWS_ACCESS_KEY_ID": "AKIATEST",
        "AWS_SECRET_ACCESS_KEY": "secret/with=equals",
        "AWS_SESSION_TOKEN": "token-value",
        "AWS_DEFAULT_REGION": "us-east-1",
    }


def test_parse_qli_export_output_requires_access_keys(view_mod):
    with pytest.raises(view_mod.ViewConfigError, match="AWS_ACCESS_KEY_ID"):
        view_mod.parse_qli_export_output("export AWS_SESSION_TOKEN=only-token\n")


def test_build_qli_export_command_with_and_without_role(view_mod):
    assert view_mod.build_qli_export_command(None) == [
        "qli",
        "aws",
        "export",
        "--shell",
        "bash",
    ]
    assert view_mod.build_qli_export_command(
        "arn:aws:iam::123456789012:role/sso_Example"
    ) == [
        "qli",
        "aws",
        "export",
        "--shell",
        "bash",
        "arn:aws:iam::123456789012:role/sso_Example",
    ]


def test_fetch_qli_credentials_uses_mocked_subprocess(view_mod, monkeypatch):
    monkeypatch.setattr(view_mod.shutil, "which", lambda _name: "/usr/bin/qli")

    calls: list[dict[str, Any]] = []

    def fake_run(command, **kwargs):
        calls.append({"command": list(command), "kwargs": kwargs})
        return subprocess.CompletedProcess(
            args=command,
            returncode=0,
            stdout=(
                "export AWS_ACCESS_KEY_ID=AKIATEST\n"
                "export AWS_SECRET_ACCESS_KEY=secret\n"
                "export AWS_SESSION_TOKEN=token\n"
            ),
            stderr="",
        )

    creds = view_mod.fetch_qli_credentials(
        role_arn="arn:aws:iam::123456789012:role/r",
        run=fake_run,
    )
    assert creds["AWS_ACCESS_KEY_ID"] == "AKIATEST"
    assert calls[0]["command"] == [
        "qli",
        "aws",
        "export",
        "--shell",
        "bash",
        "arn:aws:iam::123456789012:role/r",
    ]
    assert calls[0]["kwargs"]["capture_output"] is True


def test_fetch_qli_credentials_interactive_inherits_tty(view_mod, monkeypatch):
    monkeypatch.setattr(view_mod.shutil, "which", lambda _name: "/usr/bin/qli")
    monkeypatch.setattr(view_mod.sys.stdin, "isatty", lambda: True)

    calls: list[dict[str, Any]] = []

    def fake_run(command, **kwargs):
        calls.append({"command": list(command), "kwargs": kwargs})
        return subprocess.CompletedProcess(
            args=command,
            returncode=0,
            stdout=(
                "export AWS_ACCESS_KEY_ID=AKIATEST\n"
                "export AWS_SECRET_ACCESS_KEY=secret\n"
            ),
            stderr="",
        )

    creds = view_mod.fetch_qli_credentials(run=fake_run)
    assert creds["AWS_ACCESS_KEY_ID"] == "AKIATEST"
    assert calls[0]["command"] == ["qli", "aws", "export", "--shell", "bash"]
    kwargs = calls[0]["kwargs"]
    assert kwargs.get("capture_output") is not True
    assert kwargs["stdin"] is None
    assert kwargs["stdout"] is subprocess.PIPE
    assert kwargs["stderr"] is None


def test_fetch_qli_credentials_requires_tty_without_role(view_mod, monkeypatch):
    monkeypatch.setattr(view_mod.shutil, "which", lambda _name: "/usr/bin/qli")
    monkeypatch.setattr(view_mod.sys.stdin, "isatty", lambda: False)

    with pytest.raises(view_mod.ViewConfigError, match="TTY"):
        view_mod.fetch_qli_credentials(run=lambda *_args, **_kwargs: None)


def test_fetch_qli_credentials_redacts_aws_material_on_failure(
    view_mod, monkeypatch
):
    monkeypatch.setattr(view_mod.shutil, "which", lambda _name: "/usr/bin/qli")
    monkeypatch.setattr(view_mod.sys.stdin, "isatty", lambda: True)

    def fake_run(command, **_kwargs):
        return subprocess.CompletedProcess(
            args=command,
            returncode=1,
            # Prefer stdout-only failure detail so the AWS_* redaction path is hit.
            stdout="export AWS_ACCESS_KEY_ID=SHOULD_NOT_LEAK\n",
            stderr="",
        )

    with pytest.raises(view_mod.ViewConfigError) as raised:
        view_mod.fetch_qli_credentials(run=fake_run)

    message = str(raised.value)
    assert "SHOULD_NOT_LEAK" not in message
    assert "redacted" in message


def test_describe_view_command_is_loopback_only(view_mod):
    text = view_mod.describe_view_command(
        log_dir="s3://5a-tars-prod-data/evals/inspect/run",
        port=7575,
    )
    assert "host='127.0.0.1'" in text
    assert "port=7575" in text
    assert "0.0.0.0" not in text
    assert "s3://5a-tars-prod-data/evals/inspect/run" in text


def test_run_inspect_view_applies_and_restores_credentials(view_mod, monkeypatch):
    recorded: dict[str, Any] = {}
    monkeypatch.delenv("AWS_ACCESS_KEY_ID", raising=False)
    monkeypatch.delenv("AWS_SECRET_ACCESS_KEY", raising=False)
    monkeypatch.delenv("AWS_DEFAULT_REGION", raising=False)

    def fake_view(**kwargs):
        recorded["kwargs"] = kwargs
        recorded["key_during"] = os.environ.get("AWS_ACCESS_KEY_ID")
        recorded["secret_during"] = os.environ.get("AWS_SECRET_ACCESS_KEY")
        recorded["region_during"] = os.environ.get("AWS_DEFAULT_REGION")

    code = view_mod.run_inspect_view(
        log_dir="s3://5a-tars-prod-data/evals/inspect",
        port=7575,
        credentials={
            "AWS_ACCESS_KEY_ID": "AKIATEST",
            "AWS_SECRET_ACCESS_KEY": "secret",
        },
        view_fn=fake_view,
    )
    assert code == 0
    assert recorded["kwargs"]["host"] == "127.0.0.1"
    assert recorded["kwargs"]["log_dir"] == "s3://5a-tars-prod-data/evals/inspect"
    assert recorded["key_during"] == "AKIATEST"
    assert recorded["secret_during"] == "secret"
    assert recorded["region_during"] == "us-east-1"
    assert "AWS_ACCESS_KEY_ID" not in os.environ
    assert "AWS_SECRET_ACCESS_KEY" not in os.environ


def test_main_print_command_skips_auth_and_server(view_mod, capsys):
    code = view_mod.main(
        [
            "--print-command",
            "--log-dir",
            "s3://5a-tars-prod-data/evals/inspect/run",
            "--port",
            "7576",
        ]
    )
    assert code == 0
    out = capsys.readouterr().out
    assert "inspect_ai.view(" in out
    assert "host='127.0.0.1'" in out
    assert "port=7576" in out
    assert "http://127.0.0.1:7576" in out


def test_main_rejects_invalid_uri(view_mod, capsys):
    code = view_mod.main(["--log-dir", "./logs"])
    assert code == 2
    err = capsys.readouterr().err
    assert "s3://" in err


def test_main_use_ambient_starts_inspect_without_qli(view_mod, monkeypatch, capsys):
    recorded: dict[str, Any] = {}

    def fake_run_inspect(*, log_dir, port, credentials, view_fn=None, host=None):
        recorded["log_dir"] = log_dir
        recorded["port"] = port
        recorded["credentials"] = credentials
        recorded["host"] = host
        return 0

    monkeypatch.setattr(view_mod, "run_inspect_view", fake_run_inspect)
    monkeypatch.setattr(view_mod, "ensure_log_dir_readable", lambda **_kwargs: None)
    monkeypatch.setattr(
        view_mod,
        "fetch_qli_credentials",
        lambda **_kwargs: (_ for _ in ()).throw(AssertionError("QLI should not run")),
    )

    code = view_mod.main(
        [
            "--use-ambient-credentials",
            "--log-dir",
            "s3://5a-tars-prod-data/evals/inspect",
        ]
    )
    assert code == 0
    assert recorded["log_dir"] == "s3://5a-tars-prod-data/evals/inspect"
    assert recorded["port"] == 7575
    assert recorded["credentials"] is None
    assert "ambient AWS credentials" in capsys.readouterr().out


def test_main_qli_path_passes_credentials_only_to_viewer(
    view_mod, monkeypatch, capsys
):
    secret = "super-secret-value-do-not-print"

    monkeypatch.setattr(
        view_mod,
        "fetch_qli_credentials",
        lambda **_kwargs: {
            "AWS_ACCESS_KEY_ID": "AKIATEST",
            "AWS_SECRET_ACCESS_KEY": secret,
            "AWS_SESSION_TOKEN": "token",
        },
    )
    monkeypatch.setattr(view_mod, "ensure_log_dir_readable", lambda **_kwargs: None)

    recorded: dict[str, Any] = {}

    def fake_run_inspect(*, log_dir, port, credentials, view_fn=None, host=None):
        recorded["log_dir"] = log_dir
        recorded["credentials"] = credentials
        return 0

    monkeypatch.setattr(view_mod, "run_inspect_view", fake_run_inspect)

    code = view_mod.main(
        [
            "--log-dir",
            "s3://5a-tars-prod-data/evals/inspect/run",
            "--role-arn",
            "arn:aws:iam::123456789012:role/r",
        ]
    )
    assert code == 0
    assert recorded["credentials"]["AWS_SECRET_ACCESS_KEY"] == secret
    assert recorded["log_dir"] == "s3://5a-tars-prod-data/evals/inspect/run"
    captured = capsys.readouterr()
    assert secret not in captured.out
    assert secret not in captured.err


def test_prefix_has_objects_and_list_child_prefixes(view_mod):
    class FakeS3:
        def list_objects_v2(self, **kwargs):
            prefix = kwargs["Prefix"]
            if prefix == "evals/inspect/missing/":
                return {}
            if kwargs.get("Delimiter") == "/":
                return {
                    "CommonPrefixes": [
                        {"Prefix": "evals/inspect/2026/08/07/pr-26512/"},
                    ]
                }
            return {"Contents": [{"Key": f"{prefix}gate_summary.json"}]}

    assert (
        view_mod.prefix_has_objects(
            log_dir="s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-26512",
            s3_client=FakeS3(),
        )
        is True
    )
    assert (
        view_mod.prefix_has_objects(
            log_dir="s3://5a-tars-prod-data/evals/inspect/missing",
            s3_client=FakeS3(),
        )
        is False
    )
    children = view_mod.list_child_prefixes(
        log_dir="s3://5a-tars-prod-data/evals/inspect/2026/08/07",
        s3_client=FakeS3(),
    )
    assert children == [
        "s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-26512"
    ]


def test_list_child_prefixes_follows_s3_pagination(view_mod):
    """Regression: list_objects_v2 pages must be followed, not first-page only."""

    class FakeS3:
        def __init__(self) -> None:
            self.calls: list[dict[str, Any]] = []

        def list_objects_v2(self, **kwargs):
            self.calls.append(kwargs)
            token = kwargs.get("ContinuationToken")
            if token is None:
                return {
                    "IsTruncated": True,
                    "NextContinuationToken": "page-2",
                    "CommonPrefixes": [
                        {"Prefix": "evals/inspect/2026/08/07/pr-1/"},
                        {"Prefix": "evals/inspect/2026/08/07/pr-2/"},
                    ],
                }
            assert token == "page-2"
            return {
                "IsTruncated": False,
                "CommonPrefixes": [
                    {"Prefix": "evals/inspect/2026/08/07/pr-3/"},
                ],
            }

    client = FakeS3()
    children = view_mod.list_child_prefixes(
        log_dir="s3://5a-tars-prod-data/evals/inspect/2026/08/07",
        s3_client=client,
    )
    assert children == [
        "s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-1",
        "s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-2",
        "s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-3",
    ]
    assert len(client.calls) == 2
    assert "ContinuationToken" not in client.calls[0]
    assert client.calls[1]["ContinuationToken"] == "page-2"


def test_list_child_prefixes_honors_max_keys_across_pages(view_mod):
    class FakeS3:
        def list_objects_v2(self, **kwargs):
            assert kwargs["MaxKeys"] == 2
            return {
                "IsTruncated": True,
                "NextContinuationToken": "unused",
                "CommonPrefixes": [
                    {"Prefix": "evals/inspect/2026/08/07/pr-1/"},
                    {"Prefix": "evals/inspect/2026/08/07/pr-2/"},
                ],
            }

    children = view_mod.list_child_prefixes(
        log_dir="s3://5a-tars-prod-data/evals/inspect/2026/08/07",
        s3_client=FakeS3(),
        max_keys=2,
    )
    assert children == [
        "s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-1",
        "s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-2",
    ]


def test_ensure_log_dir_readable_reports_nearby_prefixes(view_mod):
    class FakeS3:
        def list_objects_v2(self, **kwargs):
            prefix = kwargs["Prefix"]
            if prefix.endswith("pipeline-89291/"):
                return {}
            if kwargs.get("Delimiter") == "/":
                return {
                    "CommonPrefixes": [
                        {"Prefix": "evals/inspect/2026/08/07/pr-26512/"},
                    ]
                }
            return {}

    with pytest.raises(view_mod.ViewConfigError) as raised:
        view_mod.ensure_log_dir_readable(
            log_dir=(
                "s3://5a-tars-prod-data/evals/inspect/2026/08/07/"
                "pr-27321/pipeline-89291"
            ),
            s3_client=FakeS3(),
        )
    message = str(raised.value)
    assert "No objects found" in message
    assert "pr-26512" in message


def test_main_missing_prefix_exits_before_viewer(view_mod, monkeypatch, capsys):
    monkeypatch.setattr(
        view_mod,
        "fetch_qli_credentials",
        lambda **_kwargs: {
            "AWS_ACCESS_KEY_ID": "AKIATEST",
            "AWS_SECRET_ACCESS_KEY": "secret",
        },
    )
    monkeypatch.setattr(
        view_mod,
        "ensure_log_dir_readable",
        lambda **_kwargs: (_ for _ in ()).throw(
            view_mod.ViewConfigError("No objects found under s3://example")
        ),
    )
    monkeypatch.setattr(
        view_mod,
        "run_inspect_view",
        lambda **_kwargs: (_ for _ in ()).throw(AssertionError("viewer must not start")),
    )

    code = view_mod.main(
        [
            "--log-dir",
            "s3://5a-tars-prod-data/evals/inspect/missing",
            "--role-arn",
            "arn:aws:iam::123456789012:role/r",
        ]
    )
    assert code == 2
    assert "No objects found" in capsys.readouterr().err


def test_upload_success_hint_points_at_direct_viewer(upload_mod, tmp_path):
    source = tmp_path / "logs"
    source.mkdir()
    (source / "note.txt").write_text("x\n", encoding="utf-8")

    class FakeS3:
        def upload_file(self, filename, bucket, key):
            return None

    uploaded = upload_mod.upload_directory(
        bucket="5a-tars-prod-data",
        prefix="evals/inspect/2026/08/07/local/pipeline-local",
        source=source,
        s3_client=FakeS3(),
    )
    assert uploaded

    source_text = UPLOAD_SCRIPT.read_text(encoding="utf-8")
    assert "view_inspect_logs_s3.py" in source_text
    assert "aws s3 sync" not in source_text
