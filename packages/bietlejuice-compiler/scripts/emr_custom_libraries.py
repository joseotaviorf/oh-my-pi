#!/usr/bin/env python3
"""Parse DAG cluster YAML custom_libraries for EMR bootstrap.

Used by emr_init_script.sh. Modes:

  pypi          — TSV: package\\tno_deps(0|1)\\tonly_binary(0|1)\\tignore_installed(0|1)
  whl           — one URI per line (may contain {artifacts_bucket})
  jar           — one URI per line (may contain {artifacts_bucket})
  maven         — TSV: coordinates\\trepo_or_empty\\trelative_path\\tjar_name
  requires-dist — one pip requirement per line from a local .whl METADATA

Always reads cluster.custom_libraries. When is_validation is true (env
IS_VALIDATION=1 or CLI arg 1/true), also unions validation.cluster.custom_libraries.
"""

from __future__ import annotations

import argparse
import email.parser
import importlib.metadata
import os
import re
import sys
import zipfile
from typing import Any, Dict, Iterable, List, Optional, Sequence, Set, Tuple

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
) -> List[Tuple[str, int, int, int]]:
    """Return unique (package, no_deps, only_binary, ignore_installed) rows preserving order."""
    entries: List[Tuple[str, int, int, int]] = []
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
        ignore_installed = 1 if pypi.get("ignore_installed") in _TRUTHY else 0
        entries.append((pkg, no_deps, only_binary, ignore_installed))
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


def _should_skip_requires_dist_marker(marker: str) -> bool:
    """Skip deps gated on a requested extra; keep default-runtime and env markers.

    PEP 508: ``extra == "foo"`` applies only when that extra is requested;
    ``extra != "foo"`` applies when it is not (default install). Bootstrap
    installs wheels with no extra, so only ``extra==`` lines are skipped.
    """
    normalized = marker.strip().lower().replace(" ", "")
    return "extra==" in normalized


def _normalize_requires_dist(raw: str) -> Optional[str]:
    """Turn a METADATA Requires-Dist value into a pip requirement, or None to skip."""
    value = (raw or "").strip()
    if not value:
        return None
    if ";" in value:
        req, marker = value.split(";", 1)
        if _should_skip_requires_dist_marker(marker):
            return None
        value = req.strip()
    return value or None


def extract_wheel_requires_dist(whl_path: str) -> List[str]:
    """Return unique pip requirements from a wheel's METADATA ``Requires-Dist``.

    Used by EMR bootstrap before ``pip install --no-deps`` on custom whls so
    client/model wheels get their runtime deps under EMR_CONSTRAINTS. Extra-
    gated requirements (``; extra == ...``) are skipped. Environment markers
    other than extras are stripped and the base requirement is returned so the
    bootstrap Python version can still install the dep (pip then resolves).
    """
    path = os.fspath(whl_path)
    if not path.endswith(".whl") or not os.path.isfile(path):
        raise FileNotFoundError(f"wheel not found: {path}")

    requirements: List[str] = []
    seen = set()
    with zipfile.ZipFile(path) as zf:
        metadata_name = next(
            (
                name
                for name in zf.namelist()
                if name.endswith(".dist-info/METADATA") and name.count("/") == 1
            ),
            None,
        )
        if metadata_name is None:
            return []
        raw = zf.read(metadata_name).decode("utf-8", errors="replace")

    message = email.parser.Parser().parsestr(raw)
    for header in message.get_all("Requires-Dist", failobj=[]):
        req = _normalize_requires_dist(header)
        if not req or req in seen:
            continue
        seen.add(req)
        requirements.append(req)
    return requirements


def _normalized_project_name(name: str) -> str:
    return name.lower().replace("-", "_").replace(".", "_")


def _requirement_project_name(req: str) -> Optional[str]:
    match = re.match(
        r"^\s*([A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)",
        req,
    )
    return match.group(1) if match else None


def _parse_constraint_package_names(constraints_path: str) -> Set[str]:
    names: Set[str] = set()
    with open(constraints_path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            match = re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)", line)
            if match:
                names.add(_normalized_project_name(match.group(1)))
    return names


def _is_distribution_installed(project_name: str) -> bool:
    target = _normalized_project_name(project_name)
    for dist in importlib.metadata.distributions():
        dist_name = dist.metadata.get("Name") if dist.metadata else None
        if dist_name and _normalized_project_name(dist_name) == target:
            return True
    return False


def filter_requires_dist_for_emr_constraints(
    requirements: List[str], constraints_path: str
) -> Tuple[List[str], List[str]]:
    """Drop wheel pins for packages bootstrap already installed under EMR_CONSTRAINTS.

    Client wheels often pin exact versions (e.g. ``requests==2.32.2``) that conflict
    with EMR floor pins (``requests>=2.32.3``). When the distribution is already
    installed, pip only needs the remaining Requires-Dist entries.
    """
    if not os.path.isfile(constraints_path):
        raise FileNotFoundError(f"constraints file not found: {constraints_path}")

    constrained = _parse_constraint_package_names(constraints_path)
    kept: List[str] = []
    skipped: List[str] = []
    for req in requirements:
        name = _requirement_project_name(req)
        if (
            name
            and _normalized_project_name(name) in constrained
            and _is_distribution_installed(name)
        ):
            skipped.append(req)
            continue
        kept.append(req)
    return kept, skipped


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Extract custom_libraries entries for EMR bootstrap"
    )
    parser.add_argument(
        "mode",
        choices=("pypi", "whl", "jar", "maven", "requires-dist"),
        help="Which custom_libraries type to emit",
    )
    parser.add_argument(
        "path",
        help=(
            "Path to *_cluster.yml / *_declaration.yml, or to a local .whl "
            "when mode is requires-dist"
        ),
    )
    parser.add_argument(
        "is_validation",
        nargs="?",
        default=None,
        help=(
            "1/true to also union validation.cluster.custom_libraries; "
            "for requires-dist mode, path to EMR pip constraints file"
        ),
    )
    args = parser.parse_args(list(argv) if argv is not None else None)

    if args.mode == "requires-dist":
        try:
            reqs = extract_wheel_requires_dist(args.path)
            if args.is_validation and os.path.isfile(args.is_validation):
                reqs, skipped = filter_requires_dist_for_emr_constraints(
                    reqs, args.is_validation
                )
                for req in skipped:
                    print(
                        f"    Skipping Requires-Dist {req} "
                        "(already installed under EMR_CONSTRAINTS)",
                        file=sys.stderr,
                    )
            for req in reqs:
                print(req)
        except (OSError, zipfile.BadZipFile, ValueError) as exc:
            print(f"Error: {exc}", file=sys.stderr)
            return 1
        return 0

    data = _load_yaml(args.path)
    is_validation = _parse_is_validation(args.is_validation)

    if args.mode == "pypi":
        for pkg, no_deps, only_binary, ignore_installed in extract_pypi_packages(
            data, is_validation=is_validation
        ):
            print(f"{pkg}\t{no_deps}\t{only_binary}\t{ignore_installed}")
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
