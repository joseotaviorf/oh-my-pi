#!/usr/bin/env python3
"""Parse DAG cluster YAML custom_libraries for EMR bootstrap.

Used by emr_init_script.sh. Modes:

  pypi  — TSV: package\\tno_deps(0|1)\\tonly_binary(0|1)
  whl   — one URI per line (may contain {artifacts_bucket})
  jar   — one URI per line (may contain {artifacts_bucket})
  maven — TSV: coordinates\\trepo_or_empty\\trelative_path\\tjar_name

Always reads cluster.custom_libraries. When is_validation is true (env
IS_VALIDATION=1 or CLI arg 1/true), also unions validation.cluster.custom_libraries.
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

import yaml

_TRUTHY = frozenset({True, "true", "True", 1, "1"})
# Sentinel for empty maven.repo in TSV — bash ``read`` collapses consecutive tabs,
# which would shift relative/jar_name columns when repo is blank.
_MAVEN_REPO_NONE = "-"


def _load_yaml(path: str) -> Dict[str, Any]:
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    if not isinstance(data, dict):
        return {}
    return data


def _iter_custom_libraries(
    data: Dict[str, Any], *, is_validation: bool
) -> Iterable[Any]:
    cluster = data.get("cluster") or {}
    libs = cluster.get("custom_libraries")
    if isinstance(libs, list):
        yield from libs
    if is_validation:
        validation_cluster = (data.get("validation") or {}).get("cluster") or {}
        validation_libs = validation_cluster.get("custom_libraries")
        if isinstance(validation_libs, list):
            yield from validation_libs


def extract_pypi_packages(
    data: Dict[str, Any], *, is_validation: bool = False
) -> List[Tuple[str, int, int]]:
    """Return unique (package, no_deps, only_binary) rows preserving order."""
    entries: List[Tuple[str, int, int]] = []
    seen = set()
    for item in _iter_custom_libraries(data, is_validation=is_validation):
        if not isinstance(item, dict):
            continue
        pypi = item.get("pypi")
        if not isinstance(pypi, dict):
            continue
        package = pypi.get("package")
        if not package:
            continue
        pkg = str(package).strip()
        if not pkg or pkg in seen:
            continue
        seen.add(pkg)
        no_deps = 1 if pypi.get("no_deps") in _TRUTHY else 0
        only_binary = 1 if pypi.get("only_binary") in _TRUTHY else 0
        entries.append((pkg, no_deps, only_binary))
    return entries


def extract_uris(
    data: Dict[str, Any],
    *,
    key: str,
    is_validation: bool = False,
) -> List[str]:
    """Return unique string URIs for ``jar`` or ``whl`` entries."""
    uris: List[str] = []
    seen = set()
    for item in _iter_custom_libraries(data, is_validation=is_validation):
        if not isinstance(item, dict):
            continue
        value = item.get(key)
        if isinstance(value, str) and value.strip():
            uri = value.strip()
            if uri not in seen:
                seen.add(uri)
                uris.append(uri)
    return uris


def gav_to_maven_path(coordinates: str) -> Tuple[str, str, str, str]:
    """Parse ``group:artifact:version`` into Maven layout parts.

    Returns ``(group_path, artifact, version, jar_name)`` where
    ``group_path`` uses ``/`` separators and ``jar_name`` is
    ``{artifact}-{version}.jar``.
    """
    parts = [p.strip() for p in str(coordinates).split(":")]
    if len(parts) != 3 or not all(parts):
        raise ValueError(
            f"maven coordinates must be group:artifact:version (got: {coordinates!r})"
        )
    group, artifact, version = parts
    group_path = group.replace(".", "/")
    jar_name = f"{artifact}-{version}.jar"
    return group_path, artifact, version, jar_name


def maven_relative_path(coordinates: str) -> str:
    """Return ``group/path/artifact/version/artifact-version.jar`` for a GAV."""
    group_path, artifact, version, jar_name = gav_to_maven_path(coordinates)
    return f"{group_path}/{artifact}/{version}/{jar_name}"


def extract_maven_coords(
    data: Dict[str, Any], *, is_validation: bool = False
) -> List[Tuple[str, str]]:
    """Return unique ``(coordinates, repo)`` rows preserving order.

    ``repo`` is empty when unset (caller defaults to Maven Central).
    """
    entries: List[Tuple[str, str]] = []
    seen = set()
    for item in _iter_custom_libraries(data, is_validation=is_validation):
        if not isinstance(item, dict):
            continue
        maven = item.get("maven")
        if not isinstance(maven, dict):
            continue
        coordinates = maven.get("coordinates")
        if not coordinates:
            continue
        coords = str(coordinates).strip()
        if not coords or coords in seen:
            continue
        # Validate GAV early so bootstrap fails before download loops.
        gav_to_maven_path(coords)
        seen.add(coords)
        repo = maven.get("repo")
        repo_str = str(repo).strip() if repo else ""
        entries.append((coords, repo_str))
    return entries


def _parse_is_validation(raw: Optional[str]) -> bool:
    if raw is None:
        return os.environ.get("IS_VALIDATION") == "1"
    return str(raw).strip().lower() in {"1", "true", "yes"}


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Extract custom_libraries entries for EMR bootstrap"
    )
    parser.add_argument(
        "mode",
        choices=("pypi", "whl", "jar", "maven"),
        help="Which custom_libraries type to emit",
    )
    parser.add_argument(
        "cluster_yaml", help="Path to *_cluster.yml / *_declaration.yml"
    )
    parser.add_argument(
        "is_validation",
        nargs="?",
        default=None,
        help="1/true to also union validation.cluster.custom_libraries",
    )
    args = parser.parse_args(list(argv) if argv is not None else None)

    data = _load_yaml(args.cluster_yaml)
    is_validation = _parse_is_validation(args.is_validation)

    if args.mode == "pypi":
        for pkg, no_deps, only_binary in extract_pypi_packages(
            data, is_validation=is_validation
        ):
            print(f"{pkg}\t{no_deps}\t{only_binary}")
        return 0

    if args.mode == "maven":
        try:
            for coords, repo in extract_maven_coords(data, is_validation=is_validation):
                relative = maven_relative_path(coords)
                jar_name = gav_to_maven_path(coords)[3]
                # Never emit an empty repo field (bash read field-shift).
                repo_out = repo if repo else _MAVEN_REPO_NONE
                print(f"{coords}\t{repo_out}\t{relative}\t{jar_name}")
        except ValueError as exc:
            print(f"Error: {exc}", file=sys.stderr)
            return 1
        return 0

    for uri in extract_uris(data, key=args.mode, is_validation=is_validation):
        print(uri)
    return 0


if __name__ == "__main__":
    sys.exit(main())
