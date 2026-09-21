"""Tests for offline FAIR metadata validation CLI."""

from pathlib import Path
from typing import Any, Callable, Dict
from unittest import mock

import pytest
import yaml

from bietlejuice.governance.fairness_assessment import validate_metadata_cli
from bietlejuice.governance.fairness_assessment.validate_metadata_cli import (
    _git_branch_files,
    _paths_for_owner,
    _resolve_paths,
    _scope_label,
    audit_scope_paths,
    collect_distinct_owners,
    resolve_scope_paths,
    validate_metadata_file,
)

OWNER = "owner@quintoandar.com.br"
_OMIT = object()


def _write_meta(path: Path, **overrides: Any) -> Path:
    """Write a valid clean+ metadata YAML; ``key=_OMIT`` drops a default key."""
    path.parent.mkdir(parents=True, exist_ok=True)
    meta: Dict[str, Any] = {
        "database_name": "db",
        "table_name": path.stem,
        "owner": OWNER,
        "domain": "Cross",
        "description": f"One row per {path.stem}; consumed by analytics; daily refresh.",
        "columns": {"id": {"description": "Surrogate primary key for the entity row."}},
    }
    for key, value in overrides.items():
        if value is _OMIT:
            meta.pop(key, None)
        else:
            meta[key] = value
    path.write_text(yaml.dump(meta), encoding="utf-8")
    return path


@pytest.fixture
def good_metadata(tmp_path: Path) -> Path:
    return _write_meta(
        tmp_path
        / "dags"
        / "test_domain"
        / "test_dag"
        / "metadata"
        / "clean"
        / "orders.yml",
        database_name="datalake_test_clean",
        domain="For Rent",
        columns={
            "id_order": {
                "description": "Surrogate primary key for the order in the rental funnel."
            }
        },
    )


# --------------------------------------------------------------------------- #
# validate_metadata_file
# --------------------------------------------------------------------------- #
def test_validate_metadata_file_passes(good_metadata: Path) -> None:
    ok, blocking = validate_metadata_file(good_metadata)
    assert ok, blocking
    assert not blocking


@pytest.mark.parametrize(
    "mutate, expected_substr",
    [
        pytest.param(
            lambda d: d["columns"]["id_order"].update(description="id order"),
            "F2-02",
            id="non_substantive_description",
        ),
        pytest.param(
            lambda d: d.update(columns=["id_order"]),
            "columns must be a mapping",
            id="columns_not_mapping",
        ),
        pytest.param(
            lambda d: d["columns"].update(id_order="not a dict"),
            "column 'id_order' must be a mapping",
            id="column_meta_not_mapping",
        ),
    ],
)
def test_validate_metadata_file_blocking_shapes(
    good_metadata: Path,
    mutate: Callable[[Dict[str, Any]], None],
    expected_substr: str,
) -> None:
    data = yaml.safe_load(good_metadata.read_text(encoding="utf-8"))
    mutate(data)
    good_metadata.write_text(yaml.dump(data), encoding="utf-8")
    # Act
    ok, blocking = validate_metadata_file(good_metadata)
    # Assert
    assert not ok
    assert any(expected_substr in issue for issue in blocking)


def test_validate_metadata_file_skips_f2_02_on_raw(tmp_path: Path) -> None:
    raw = _write_meta(
        tmp_path / "dags" / "g" / "d" / "metadata" / "raw" / "t.yml",
        owner=_OMIT,
        columns={"id": {"description": "id"}},
    )
    # Act — raw columns allowed; F2-02 not applied
    ok, blocking = validate_metadata_file(raw)
    # Assert
    assert ok
    assert not blocking


def test_validate_metadata_file_skips_partition_columns_case_insensitive(
    good_metadata: Path,
) -> None:
    data = yaml.safe_load(good_metadata.read_text(encoding="utf-8"))
    data["columns"]["Year"] = {"description": "Year"}
    data["columns"]["MONTH"] = {"description": "Month"}
    good_metadata.write_text(yaml.dump(data), encoding="utf-8")
    # Act — partition cols excluded like production assessment
    ok, blocking = validate_metadata_file(good_metadata)
    # Assert
    assert ok, blocking


def test_validate_metadata_file_skips_cdc_plumbing_columns(
    good_metadata: Path,
) -> None:
    data = yaml.safe_load(good_metadata.read_text(encoding="utf-8"))
    data["columns"]["op_cdc"] = {"description": "op cdc"}
    data["columns"]["ts_cdc_transaction"] = {"description": "ts"}
    data["columns"]["ts_database_transaction"] = {"description": "ts"}
    good_metadata.write_text(yaml.dump(data), encoding="utf-8")
    ok, blocking = validate_metadata_file(good_metadata)
    assert ok, blocking


def test_validate_metadata_file_fails_on_unreadable_yaml(tmp_path: Path) -> None:
    bad = tmp_path / "dags" / "g" / "metadata" / "clean" / "bad.yml"
    bad.parent.mkdir(parents=True)
    bad.write_text("columns: [\n", encoding="utf-8")
    # Act
    ok, blocking = validate_metadata_file(bad)
    # Assert
    assert not ok
    assert blocking


def test_table_tdq_blocks_non_substantive_description(good_metadata: Path) -> None:
    data = yaml.safe_load(good_metadata.read_text(encoding="utf-8"))
    data["description"] = "Orders table in datalake_test_clean."
    good_metadata.write_text(yaml.dump(data), encoding="utf-8")
    ok, blocking = validate_metadata_file(good_metadata)
    assert not ok
    assert any("F2-01 table_description_not_substantive" in issue for issue in blocking)


@pytest.mark.parametrize(
    "description",
    [
        pytest.param("", id="empty_string"),
        pytest.param("   ", id="whitespace_only"),
        pytest.param(None, id="null"),
    ],
)
def test_empty_table_description_uses_missing_code(
    good_metadata: Path,
    description: str | None,
) -> None:
    data = yaml.safe_load(good_metadata.read_text(encoding="utf-8"))
    data["description"] = description
    good_metadata.write_text(yaml.dump(data), encoding="utf-8")
    ok, blocking = validate_metadata_file(good_metadata)
    assert not ok
    assert any("F2-01 table_description_missing" in issue for issue in blocking)
    assert not any("table_description_not_substantive" in issue for issue in blocking)


# --------------------------------------------------------------------------- #
# _git_branch_files
# --------------------------------------------------------------------------- #
@mock.patch(
    "bietlejuice.governance.fairness_assessment.validate_metadata_cli.subprocess.check_output"
)
@mock.patch(
    "bietlejuice.governance.fairness_assessment.validate_metadata_cli.fetch_diff_base"
)
def test_git_branch_files_filters_metadata_paths(
    mock_fetch: mock.MagicMock,
    mock_check_output: mock.MagicMock,
) -> None:
    mock_check_output.return_value = (
        "M\tdags/foo/metadata/clean/table.yml\n"
        "A\tdags/bar/metadata/enrich/other.yml\n"
        "D\tdags/foo/metadata/clean/deleted.yml\n"
        "M\tdags/foo/queries/clean/table.sql\n"
        "T\tdags/foo/metadata/clean/type_changed.yml\n"
    )
    # Act
    paths = _git_branch_files("feature-branch")
    # Assert — only upserted (M/A) metadata YAML kept
    assert paths == [
        Path("dags/foo/metadata/clean/table.yml"),
        Path("dags/bar/metadata/enrich/other.yml"),
    ]
    mock_fetch.assert_called_once_with("origin/master")
    assert mock_check_output.call_args[0][0] == [
        "git",
        "diff",
        "--no-commit-id",
        "--name-status",
        "--no-renames",
        "-r",
        "origin/master...HEAD",
    ]


@mock.patch(
    "bietlejuice.governance.fairness_assessment.validate_metadata_cli.subprocess.check_output"
)
@mock.patch(
    "bietlejuice.governance.fairness_assessment.validate_metadata_cli.fetch_diff_base"
)
def test_git_branch_files_uses_full_pr_diff_when_target_branch_is_master_on_pull_request(
    mock_fetch: mock.MagicMock,
    mock_check_output: mock.MagicMock,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    mock_check_output.return_value = "M\tdags/foo/metadata/clean/table.yml\n"
    monkeypatch.setenv("CI_PIPELINE_EVENT", "pull_request")
    monkeypatch.delenv("CI_COMMIT_TARGET_BRANCH", raising=False)
    # Act
    _git_branch_files("master")
    # Assert — Woodpecker sets CI_COMMIT_BRANCH=master on PRs targeting master
    assert mock_check_output.call_args[0][0][-1] == "origin/master...HEAD"


@mock.patch(
    "bietlejuice.governance.fairness_assessment.validate_metadata_cli.subprocess.check_output"
)
@mock.patch(
    "bietlejuice.governance.fairness_assessment.validate_metadata_cli.fetch_diff_base"
)
def test_git_branch_files_fetches_the_diff_base_it_compares_against(
    mock_fetch: mock.MagicMock,
    mock_check_output: mock.MagicMock,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    mock_check_output.return_value = "M\tdags/foo/metadata/clean/table.yml\n"
    monkeypatch.setenv("CI_PIPELINE_EVENT", "pull_request")
    monkeypatch.setenv("CI_COMMIT_TARGET_BRANCH", "development")
    _git_branch_files("development")
    assert mock_check_output.call_args[0][0][-1] == "origin/development...HEAD"
    mock_fetch.assert_called_once_with("origin/development")


# --------------------------------------------------------------------------- #
# resolve_scope_paths
# --------------------------------------------------------------------------- #
def test_resolve_scope_paths_by_domain(tmp_path: Path) -> None:
    meta = _write_meta(
        tmp_path / "dags" / "gov" / "dag_a" / "metadata" / "clean" / "t.yml"
    )
    other = tmp_path / "dags" / "other" / "metadata" / "clean" / "x.yml"
    other.parent.mkdir(parents=True)
    other.write_text("database_name: db\ntable_name: x\n", encoding="utf-8")
    # Act
    assert resolve_scope_paths(tmp_path, domain="gov") == [meta]


def test_resolve_scope_paths_by_owner(tmp_path: Path) -> None:
    owned = _write_meta(tmp_path / "dags" / "a" / "metadata" / "clean" / "owned.yml")
    # Act
    assert resolve_scope_paths(tmp_path, owner=OWNER) == [owned]


def test_resolve_scope_paths_domain_and_owner_intersect(tmp_path: Path) -> None:
    owned_in_gov = _write_meta(
        tmp_path / "dags" / "gov" / "dag_a" / "metadata" / "clean" / "owned.yml"
    )
    _write_meta(
        tmp_path / "dags" / "gov" / "dag_b" / "metadata" / "clean" / "other.yml",
        owner="other@quintoandar.com.br",
    )
    _write_meta(tmp_path / "dags" / "other" / "metadata" / "clean" / "owned2.yml")
    # Act — domain ∩ owner, not whole domain or owner repo-wide alone
    assert resolve_scope_paths(tmp_path, domain="gov", owner=OWNER) == [owned_in_gov]


def test_resolve_scope_paths_by_fqn(tmp_path: Path) -> None:
    raw = _write_meta(
        tmp_path / "dags" / "a" / "metadata" / "raw" / "orders.yml",
        database_name="datalake_x_raw",
        table_name="orders",
        columns=_OMIT,
    )
    clean = _write_meta(
        tmp_path / "dags" / "a" / "metadata" / "clean" / "orders.yml",
        database_name="datalake_x_raw",
        table_name="orders",
        columns=_OMIT,
    )
    # Act — all layers sharing the FQN (sorted path order)
    assert resolve_scope_paths(tmp_path, fqn="datalake_x_raw.orders") == sorted(
        [raw, clean]
    )


def test_resolve_scope_paths_empty_when_domain_owner_intersection_empty(
    tmp_path: Path,
) -> None:
    _write_meta(
        tmp_path / "dags" / "gov" / "metadata" / "clean" / "t.yml",
        owner="other@quintoandar.com.br",
    )
    # Act
    assert resolve_scope_paths(tmp_path, domain="gov", owner=OWNER) == []


@pytest.mark.parametrize(
    "kwargs, match",
    [
        pytest.param({"domain": "../outside"}, "Invalid domain name", id="domain"),
        pytest.param({"dag": "gov/../../outside"}, "Invalid --dag", id="dag"),
    ],
)
def test_resolve_scope_paths_rejects_path_traversal(
    tmp_path: Path,
    kwargs: Dict[str, str],
    match: str,
) -> None:
    (tmp_path / "dags" / "gov").mkdir(parents=True)
    # Act / Assert
    with pytest.raises(ValueError, match=match):
        resolve_scope_paths(tmp_path, **kwargs)


def test_paths_for_owner_skips_unreadable_yaml(tmp_path: Path) -> None:
    good = _write_meta(tmp_path / "dags" / "a" / "metadata" / "clean" / "good.yml")
    bad = tmp_path / "dags" / "b" / "metadata" / "clean" / "bad.yml"
    bad.parent.mkdir(parents=True)
    bad.write_text("owner: [ broken yaml\n", encoding="utf-8")
    # Act — scan continues; bad file ignored
    assert _paths_for_owner(tmp_path / "dags", OWNER) == {good}


# --------------------------------------------------------------------------- #
# audit_scope_paths / collect_distinct_owners
# --------------------------------------------------------------------------- #
def test_audit_scope_paths_raw_columns_optional_not_blocking(tmp_path: Path) -> None:
    _write_meta(
        tmp_path / "dags" / "g" / "d" / "metadata" / "raw" / "t.yml",
        columns={"id": {}},
    )
    _write_meta(
        tmp_path / "dags" / "g" / "d" / "metadata" / "clean" / "t.yml",
        columns={"id": {"description": "id"}},
    )
    paths = resolve_scope_paths(tmp_path, domain="g")
    # Act
    audit = audit_scope_paths(paths)
    # Assert — raw columns optional; clean fails F2-01/F2-02 when descriptions weak
    assert not audit.gate_b_passed
    assert audit.gate_a_passed
    assert audit.raw_file_count == 1
    assert audit.raw_with_columns_count == 1


def test_audit_scope_paths_includes_core_in_gate_b(tmp_path: Path) -> None:
    core = _write_meta(
        tmp_path / "dags" / "core" / "core_house" / "metadata" / "core" / "house.yml",
        database_name="core_house",
        table_name="house",
        columns={"id_house": {"description": "id"}},
    )
    # Act
    audit = audit_scope_paths([core])
    # Assert — core counts as clean+ for Gate B
    assert not audit.gate_b_passed
    assert len(audit.f2_failures) == 1
    assert audit.f2_failures[0][0] == core
    assert any("F2-02" in issue for issue in audit.f2_failures[0][1])


def test_collect_distinct_owners_marks_unverified(tmp_path: Path) -> None:
    meta = _write_meta(tmp_path / "dags" / "x" / "metadata" / "clean" / "t.yml")
    # Act — ACTIVE/INACTIVE requires online verification
    rows, yaml_errors = collect_distinct_owners([meta])
    # Assert
    assert yaml_errors == []
    assert rows == [(OWNER, 1, "UNVERIFIED")]


def test_audit_scope_paths_missing_inventory_path(tmp_path: Path) -> None:
    missing = tmp_path / "dags" / "g" / "metadata" / "clean" / "gone.yml"
    # Act
    audit = audit_scope_paths([missing])
    # Assert
    assert audit.missing_paths == [missing]
    assert not audit.gate_a_passed


def test_audit_scope_paths_reports_yaml_load_warnings(tmp_path: Path) -> None:
    bad = tmp_path / "dags" / "g" / "metadata" / "clean" / "bad.yml"
    bad.parent.mkdir(parents=True)
    bad.write_text("columns: [\n", encoding="utf-8")
    # Act
    audit = audit_scope_paths([bad])
    # Assert
    assert len(audit.yaml_load_errors) == 1
    assert audit.owner_rows == []
    assert not audit.gate_a_passed
    assert not audit.gate_b_passed


def test_audit_scope_paths_fails_raw_only_unreadable_yaml(tmp_path: Path) -> None:
    # Arrange — raw-only scope with no parseable YAML must not pass both gates
    raw = tmp_path / "dags" / "g" / "d" / "metadata" / "raw" / "t.yml"
    raw.parent.mkdir(parents=True)
    raw.write_text("owner: [ broken\n", encoding="utf-8")
    # Act
    audit = audit_scope_paths([raw])
    # Assert
    assert audit.raw_file_count == 1
    assert audit.parsed_file_count == 0
    assert not audit.gate_a_passed
    assert audit.gate_b_passed


# --------------------------------------------------------------------------- #
# _scope_label / _resolve_paths
# --------------------------------------------------------------------------- #
def test_scope_label_explicit_files_ignores_scope_flags() -> None:
    from argparse import Namespace

    args = Namespace(
        domain="governance", owner=OWNER, dag=None, fqn=None, files=["a.yml"]
    )
    # Act
    label = _scope_label(args, explicit_file_count=2)
    # Assert
    assert label == "explicit file list (2 files)"
    assert "domain=" not in label


def test_resolve_paths_warns_when_scope_flags_with_files(
    tmp_path: Path,
    capsys,
) -> None:
    from argparse import Namespace

    meta = tmp_path / "dags" / "g" / "metadata" / "clean" / "t.yml"
    meta.parent.mkdir(parents=True)
    meta.write_text("database_name: db\ntable_name: t\n", encoding="utf-8")
    args = Namespace(
        files=[str(meta)],
        domain="governance",
        owner=None,
        dag=None,
        fqn=None,
        branch=None,
    )
    # Act
    paths, label = _resolve_paths(args, tmp_path)
    captured = capsys.readouterr()
    # Assert — explicit files win; scope flags ignored with a warning
    assert paths == [meta]
    assert label == "explicit file list (1 file)"
    assert "ignored when -f/--file is set" in captured.err


def test_resolve_paths_warns_when_branch_with_scope_flags(
    tmp_path: Path,
    capsys,
) -> None:
    from argparse import Namespace

    meta = _write_meta(tmp_path / "dags" / "g" / "metadata" / "clean" / "t.yml")
    args = Namespace(
        files=None, branch="feature-branch", domain="g", owner=None, dag=None, fqn=None
    )
    # Act
    paths, label = _resolve_paths(args, tmp_path)
    captured = capsys.readouterr()
    # Assert — scope wins; branch diff is not applied
    assert paths == [meta]
    assert label == "domain=g"
    assert "ignored when --domain/--owner/--dag/--fqn is set" in captured.err


# --------------------------------------------------------------------------- #
# main — exit codes
# --------------------------------------------------------------------------- #
def test_main_fails_when_all_paths_missing(tmp_path: Path, monkeypatch) -> None:
    missing = tmp_path / "dags" / "foo" / "metadata" / "clean" / "gone.yml"
    monkeypatch.chdir(tmp_path)
    assert validate_metadata_cli.main(["-f", str(missing)]) == 1


def test_main_fails_when_some_paths_missing_and_one_passes(
    good_metadata: Path,
    tmp_path: Path,
    monkeypatch,
) -> None:
    # PR diff must not pass if any listed path is missing on disk
    missing = tmp_path / "dags" / "foo" / "metadata" / "clean" / "gone.yml"
    monkeypatch.chdir(tmp_path)
    assert (
        validate_metadata_cli.main(["-f", str(good_metadata), "-f", str(missing)]) == 1
    )


def test_main_fails_when_missing_path_and_only_raw_on_disk(
    tmp_path: Path,
    monkeypatch,
) -> None:
    # missing + raw skipped leaves validated=0 but missing>0
    raw = _write_meta(
        tmp_path / "dags" / "g" / "d" / "metadata" / "raw" / "t.yml",
        owner=_OMIT,
        columns=_OMIT,
    )
    missing = tmp_path / "dags" / "g" / "d" / "metadata" / "clean" / "gone.yml"
    monkeypatch.chdir(tmp_path)
    assert validate_metadata_cli.main(["-f", str(raw), "-f", str(missing)]) == 1


def test_main_succeeds_when_only_raw_files_in_scope(
    tmp_path: Path, monkeypatch
) -> None:
    # raw-only diff is skipped; not a failure
    raw = _write_meta(
        tmp_path / "dags" / "g" / "d" / "metadata" / "raw" / "t.yml", columns=_OMIT
    )
    monkeypatch.chdir(tmp_path)
    assert validate_metadata_cli.main(["-f", str(raw)]) == 0


def test_main_fails_on_f2_02_blocking_issue(good_metadata: Path, monkeypatch) -> None:
    data = yaml.safe_load(good_metadata.read_text(encoding="utf-8"))
    data["columns"]["id_order"]["description"] = "id order"
    good_metadata.write_text(yaml.dump(data), encoding="utf-8")
    monkeypatch.chdir(good_metadata.parents[4])
    assert validate_metadata_cli.main(["-f", str(good_metadata)]) == 1


@pytest.mark.parametrize(
    "argv",
    [
        pytest.param(["--audit", "--owner", "   "], id="whitespace_owner"),
        pytest.param(["--audit", "--domain", "no_such_folder"], id="unknown_domain"),
        pytest.param(["--audit", "--fqn", "not-a-valid-fqn"], id="invalid_fqn"),
    ],
)
def test_main_audit_exits_one_on_invalid_scope(
    tmp_path: Path,
    monkeypatch,
    argv,
) -> None:
    (tmp_path / "dags").mkdir(exist_ok=True)
    monkeypatch.chdir(tmp_path)
    # Act / Assert
    assert validate_metadata_cli.main(argv) == 1


@pytest.mark.parametrize(
    "argv",
    [
        pytest.param(["--audit"], id="bare_audit"),
        pytest.param(["--audit", "-b", "feature"], id="audit_with_branch"),
    ],
)
def test_main_audit_requires_scope_or_files(
    tmp_path: Path,
    monkeypatch,
    capsys,
    argv,
) -> None:
    # Arrange — must not silently shrink a scope audit to the branch diff
    called = []
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(
        validate_metadata_cli,
        "_git_branch_files",
        lambda *_a, **_k: called.append(True) or [],
    )
    # Act
    code = validate_metadata_cli.main(argv)
    # Assert — refused before resolving any git diff
    assert code == 1
    assert "requires scope flags" in capsys.readouterr().err
    assert called == []


def test_main_exits_zero_when_pr_diff_has_no_metadata(
    tmp_path: Path,
    monkeypatch,
) -> None:
    # Woodpecker step when diff has no metadata YAML (non-audit)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(
        validate_metadata_cli, "_resolve_paths", lambda *_a, **_k: ([], "branch=x")
    )
    assert validate_metadata_cli.main([]) == 0


def test_main_audit_fails_raw_only_unreadable_yaml(tmp_path: Path, monkeypatch) -> None:
    raw = tmp_path / "dags" / "g" / "d" / "metadata" / "raw" / "t.yml"
    raw.parent.mkdir(parents=True)
    raw.write_text("owner: [ broken\n", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    assert validate_metadata_cli.main(["--audit", "-f", str(raw)]) == 1


def test_main_audit_fails_when_clean_file_has_missing_owner(
    tmp_path: Path, monkeypatch
) -> None:
    meta = _write_meta(
        tmp_path / "dags" / "g" / "metadata" / "clean" / "t.yml", owner=_OMIT
    )
    monkeypatch.chdir(tmp_path)
    # Act / Assert — Gate A fails on MISSING owner
    assert validate_metadata_cli.main(["--audit", "-f", str(meta)]) == 1


@pytest.mark.parametrize(
    "argv",
    [
        pytest.param(["--audit", "--domain", ".."], id="domain"),
        pytest.param(["--audit", "--dag", "gov/../other"], id="dag"),
    ],
)
def test_main_rejects_path_traversal(tmp_path: Path, monkeypatch, argv) -> None:
    (tmp_path / "dags" / "gov").mkdir(parents=True)
    monkeypatch.chdir(tmp_path)
    # Act / Assert — argparse type= rejects before main returns
    with pytest.raises(SystemExit) as exc:
        validate_metadata_cli.main(argv)
    assert exc.value.code == 2
