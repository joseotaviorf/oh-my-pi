#!/usr/bin/env python3
"""
Extract cluster: from *_declaration.yml into *_cluster.yml and generate validation: blocks.

Usage:
  python extract_cluster_validation_files.py dags/platform/
  python extract_cluster_validation_files.py dags/platform/ --source-ref <git-ref>
  python extract_cluster_validation_files.py dags/platform/ --strip-declaration
  python extract_cluster_validation_files.py dags/ --check
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import yaml
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.configuration_service import ConfigurationService
from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
    ValidationClusterSpec,
    _has_load_spark_job,
    build_validation_cluster_spec,
    normalize_databricks_cluster_topology,
)
from scripts.ci_cd.airflow_dag_builder.cluster_yaml_format import (
    assert_no_folded_catalog_namespace,
    dump_cluster_yaml,
)

REPO_ROOT = Path(__file__).resolve().parents[5]
DAGS_ROOT = REPO_ROOT / "dags"
LOGGER = QuintoAndarLogger("extract_cluster_validation_files")

TOP_LEVEL_KEYS = frozenset(
    {"dag", "workflow", "cluster", "validation", "spark_session_configs"}
)


def _declaration_paths(root: Path) -> List[Path]:
    return sorted(root.rglob("*_declaration.yml"))


def _cluster_file_paths(root: Path) -> List[Path]:
    paths: List[Path] = []
    for declaration_path in _declaration_paths(root):
        cluster_path = _cluster_file_path(declaration_path)
        if cluster_path.exists():
            paths.append(cluster_path)
    return paths


def _declaration_path_for_cluster(cluster_path: Path) -> Path:
    dag_name = cluster_path.name.replace("_cluster.yml", "")
    return cluster_path.parent / f"{dag_name}_declaration.yml"


def _cluster_file_path(declaration_path: Path) -> Path:
    dag_dir = declaration_path.parent
    dag_name = declaration_path.name.replace("_declaration.yml", "")
    return dag_dir / f"{dag_name}_cluster.yml"


def _on_disk_has_validation_stage(cluster_path: Path) -> bool:
    """DAGs with validation.cluster are still in the validation stage (skip bulk regen/check)."""
    if not cluster_path.exists():
        return False
    document = yaml.safe_load(cluster_path.read_text(encoding="utf-8")) or {}
    return bool((document.get("validation") or {}).get("cluster"))


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _normalize_cluster_file_text(text: str) -> str:
    """Compare cluster files with a single trailing newline."""
    return text.rstrip("\n") + "\n"


def _validate_cluster_file_yaml_format(cluster_path: Path, text: str) -> Optional[str]:
    """Return an error message when cluster YAML has folded catalog.namespace Jinja."""
    try:
        assert_no_folded_catalog_namespace(text)
    except ValueError as exc:
        return f"{cluster_path}: {exc}"
    return None


def _read_text_from_git(git_ref: str, repo_relative: Path) -> str:
    result = subprocess.run(
        ["git", "show", f"{git_ref}:{repo_relative.as_posix()}"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"git show {git_ref}:{repo_relative} failed: {result.stderr.strip()}"
        )
    return result.stdout


def extract_cluster_section_text(declaration_text: str) -> Optional[str]:
    """Return verbatim cluster: block including trailing newline, or None."""
    lines = declaration_text.splitlines(keepends=True)
    start_idx: Optional[int] = None
    for index, line in enumerate(lines):
        if line.startswith("cluster:"):
            start_idx = index
            break
    if start_idx is None:
        return None

    end_idx = len(lines)
    for index in range(start_idx + 1, len(lines)):
        stripped = lines[index].strip()
        if not stripped or stripped.startswith("#"):
            continue
        key = lines[index].split(":", 1)[0]
        if key in TOP_LEVEL_KEYS and not lines[index].startswith(" "):
            end_idx = index
            break

    block = "".join(lines[start_idx:end_idx])
    if not block.endswith("\n"):
        block += "\n"
    return block


def remove_cluster_section_text(declaration_text: str) -> str:
    """Remove cluster: block from declaration text without reformatting the rest."""
    lines = declaration_text.splitlines(keepends=True)
    start_idx: Optional[int] = None
    for index, line in enumerate(lines):
        if line.startswith("cluster:"):
            start_idx = index
            break
    if start_idx is None:
        return declaration_text

    end_idx = len(lines)
    for index in range(start_idx + 1, len(lines)):
        stripped = lines[index].strip()
        if not stripped or stripped.startswith("#"):
            continue
        key = lines[index].split(":", 1)[0]
        if key in TOP_LEVEL_KEYS and not lines[index].startswith(" "):
            end_idx = index
            break

    return "".join(lines[:start_idx] + lines[end_idx:])


def _parse_cluster_dict(cluster_text: str) -> dict:
    document = yaml.safe_load(cluster_text) or {}
    cluster = document.get("cluster") if "cluster" in document else document
    if not isinstance(cluster, dict):
        raise ValueError("cluster section must be a mapping")
    return cluster


def _format_validation_yaml(spec: ValidationClusterSpec) -> str:
    validation_cluster: Dict[str, Any] = {"type": spec.cluster_type}
    if spec.databricks_conn_id is not None:
        validation_cluster["databricks_conn_id"] = spec.databricks_conn_id
    if spec.access_control_list is not None:
        validation_cluster["access_control_list"] = spec.access_control_list
    if spec.custom_libraries is not None:
        validation_cluster["custom_libraries"] = spec.custom_libraries
    if spec.custom_configurations:
        validation_cluster["custom_configurations"] = spec.custom_configurations

    validation_doc: Dict[str, Any] = {"cluster": validation_cluster}
    if spec.allow_custom_spark_job:
        validation_doc["allow_custom_spark_job"] = True

    dumped = dump_cluster_yaml(validation_doc)
    lines = ["validation:"]
    for line in dumped.splitlines():
        if line.strip():
            lines.append(f"  {line}")
    return "\n".join(lines) + "\n"


def _declaration_for_cluster_path(cluster_path: Path) -> dict:
    """Load declaration merged with prod cluster args from *_cluster.yml."""
    declaration_path = _declaration_path_for_cluster(cluster_path)
    declaration = yaml.safe_load(_read_text(declaration_path)) or {}
    cluster_text = extract_cluster_section_text(_read_text(cluster_path))
    if cluster_text:
        cluster_args = _parse_cluster_dict(cluster_text)
        declaration = {**declaration, "cluster": cluster_args}
    return declaration


def _validate_allow_custom_spark_job_contract(
    cluster_content: str,
    declaration: dict,
    *,
    context_path: Path,
) -> Optional[str]:
    """
    Ensure allow_custom_spark_job in generated YAML matches declaration load_spark_job.

    Returns an error message when the contract is violated, else None.
    """
    if "validation:" not in cluster_content:
        return None
    has_load_job = _has_load_spark_job(declaration)
    has_flag = "allow_custom_spark_job:" in cluster_content
    if has_load_job and not has_flag:
        return (
            f"{context_path}: validation block missing allow_custom_spark_job "
            "(declaration has load_spark_job)"
        )
    if not has_load_job and has_flag:
        return (
            f"{context_path}: unexpected allow_custom_spark_job "
            "(declaration has no load_spark_job)"
        )
    return None


def build_cluster_file_content(
    *,
    cluster_text: str,
    declaration: dict,
    cluster_args: dict,
) -> str:
    config_service = ConfigurationService()
    normalized_args = normalize_databricks_cluster_topology(
        cluster_args, config_service
    )
    prod_block = dump_cluster_yaml({"cluster": normalized_args})
    spec = build_validation_cluster_spec(
        cluster_args=normalized_args,
        declaration=declaration,
        config_service=config_service,
    )
    content = prod_block.rstrip("\n") + "\n"
    if spec is not None:
        content += _format_validation_yaml(spec)
    return _normalize_cluster_file_text(content)


def process_declaration(
    declaration_path: Path,
    *,
    source_ref: Optional[str],
    strip_declaration: bool,
) -> Tuple[Optional[Path], Optional[str], Optional[str]]:
    """
    Returns (cluster_path, cluster_file_content, updated_declaration_text).
    cluster_file_content is None if no cluster section found.
    """
    repo_relative = declaration_path.relative_to(REPO_ROOT)
    if source_ref:
        declaration_text = _read_text_from_git(source_ref, repo_relative)
    else:
        declaration_text = _read_text(declaration_path)

    cluster_text = extract_cluster_section_text(declaration_text)
    if cluster_text is None:
        return None, None, None

    cluster_args = _parse_cluster_dict(cluster_text)
    declaration = yaml.safe_load(declaration_text) or {}
    declaration_for_validation = {**declaration, "cluster": cluster_args}

    cluster_content = build_cluster_file_content(
        cluster_text=cluster_text,
        declaration=declaration_for_validation,
        cluster_args=cluster_args,
    )
    cluster_path = _cluster_file_path(declaration_path)

    updated_declaration: Optional[str] = None
    if strip_declaration and not source_ref:
        updated_declaration = remove_cluster_section_text(declaration_text)

    return cluster_path, cluster_content, updated_declaration


def process_cluster_file(cluster_path: Path) -> Tuple[Path, Optional[str]]:
    """Regenerate *_cluster.yml from on-disk prod cluster block + declaration."""
    cluster_file_text = _read_text(cluster_path)
    cluster_text = extract_cluster_section_text(cluster_file_text)
    if cluster_text is None:
        return cluster_path, None

    declaration_path = _declaration_path_for_cluster(cluster_path)
    if not declaration_path.exists():
        raise FileNotFoundError(f"Missing declaration for {cluster_path}")

    cluster_args = _parse_cluster_dict(cluster_text)
    declaration = yaml.safe_load(_read_text(declaration_path)) or {}
    declaration_for_validation = {**declaration, "cluster": cluster_args}

    cluster_content = build_cluster_file_content(
        cluster_text=cluster_text,
        declaration=declaration_for_validation,
        cluster_args=cluster_args,
    )
    return cluster_path, cluster_content


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "path",
        type=Path,
        help="Path under dags/ (e.g. dags/platform/)",
    )
    parser.add_argument(
        "--source-ref",
        help="Git ref to read declaration cluster: from (when absent on disk)",
    )
    parser.add_argument(
        "--strip-declaration",
        action="store_true",
        help="Remove cluster: section from *_declaration.yml after writing cluster file",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit 1 if on-disk *_cluster.yml differs from generated content",
    )
    args = parser.parse_args()

    root = args.path if args.path.is_absolute() else REPO_ROOT / args.path
    if not root.exists():
        LOGGER.error("Path not found: %s", root)
        return 1

    errors: List[str] = []
    written = 0
    checked = 0
    checked_paths: set[Path] = set()

    if args.check:
        for cluster_path in _cluster_file_paths(root):
            fmt_err = _validate_cluster_file_yaml_format(
                cluster_path, _read_text(cluster_path)
            )
            if fmt_err:
                errors.append(fmt_err)

    for declaration_path in _declaration_paths(root):
        cluster_path = _cluster_file_path(declaration_path)
        if args.check and not cluster_path.exists():
            # Phased migration: skip inline cluster: until *_cluster.yml exists.
            continue
        if _on_disk_has_validation_stage(cluster_path):
            # Concluded DAGs only: do not rewrite cluster files still in validation stage.
            if args.check:
                checked_paths.add(cluster_path.resolve())
            continue

        try:
            cluster_path, cluster_content, updated_declaration = process_declaration(
                declaration_path,
                source_ref=args.source_ref,
                strip_declaration=args.strip_declaration,
            )
        except Exception as exc:  # noqa: BLE001 — CLI reports all failures
            errors.append(f"{declaration_path}: {exc}")
            continue

        if cluster_content is None:
            continue

        if args.check:
            contract_err = _validate_allow_custom_spark_job_contract(
                cluster_content,
                _declaration_for_cluster_path(cluster_path),
                context_path=cluster_path,
            )
            if contract_err:
                errors.append(contract_err)
                continue
            on_disk = _normalize_cluster_file_text(_read_text(cluster_path))
            fmt_err = _validate_cluster_file_yaml_format(cluster_path, on_disk)
            if fmt_err:
                errors.append(fmt_err)
                continue
            expected = _normalize_cluster_file_text(cluster_content)
            if on_disk != expected:
                errors.append(f"{cluster_path}: content differs from generator output")
            else:
                checked += 1
                checked_paths.add(cluster_path.resolve())
            continue

        cluster_path.parent.mkdir(parents=True, exist_ok=True)
        cluster_path.write_text(
            _normalize_cluster_file_text(cluster_content),
            encoding="utf-8",
        )
        written += 1
        checked_paths.add(cluster_path.resolve())

        if updated_declaration is not None:
            declaration_path.write_text(updated_declaration, encoding="utf-8")

        rel = cluster_path.relative_to(REPO_ROOT)
        LOGGER.info("Wrote %s", rel)

    if not args.check:
        for cluster_path in _cluster_file_paths(root):
            if cluster_path.resolve() in checked_paths:
                continue
            if _on_disk_has_validation_stage(cluster_path):
                continue
            try:
                _, cluster_content = process_cluster_file(cluster_path)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{cluster_path}: {exc}")
                continue
            if cluster_content is None:
                continue
            cluster_path.write_text(
                _normalize_cluster_file_text(cluster_content),
                encoding="utf-8",
            )
            written += 1
            checked_paths.add(cluster_path.resolve())
            rel = cluster_path.relative_to(REPO_ROOT)
            LOGGER.info("Wrote %s", rel)

    if args.check:
        for cluster_path in _cluster_file_paths(root):
            if cluster_path.resolve() in checked_paths:
                continue
            if _on_disk_has_validation_stage(cluster_path):
                continue
            try:
                _, cluster_content = process_cluster_file(cluster_path)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{cluster_path}: {exc}")
                continue
            if cluster_content is None:
                continue
            contract_err = _validate_allow_custom_spark_job_contract(
                cluster_content,
                _declaration_for_cluster_path(cluster_path),
                context_path=cluster_path,
            )
            if contract_err:
                errors.append(contract_err)
                continue
            on_disk = _normalize_cluster_file_text(_read_text(cluster_path))
            fmt_err = _validate_cluster_file_yaml_format(cluster_path, on_disk)
            if fmt_err:
                errors.append(fmt_err)
                continue
            expected = _normalize_cluster_file_text(cluster_content)
            if on_disk != expected:
                errors.append(f"{cluster_path}: content differs from generator output")
            else:
                checked += 1

    if errors:
        LOGGER.error("Errors:")
        for message in errors:
            LOGGER.error("  - %s", message)
        return 1

    if args.check:
        LOGGER.info("Checked %s cluster file(s); all match generator output.", checked)
    else:
        LOGGER.info("Wrote %s cluster file(s).", written)
    return 0


if __name__ == "__main__":
    os.chdir(REPO_ROOT)
    sys.exit(main())
