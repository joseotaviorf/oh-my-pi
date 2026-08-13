"""
Generate .table_manifest files for DAG query folders to avoid GCS glob at parse time.

Each queries/{layer}/{intermediate_path}/ directory containing .sql files gets a
.table_manifest file with one table name (basename without .sql) per line.
At parse time, list_queries_files_in_composer reads the manifest when present
instead of globbing, reducing 2-5s latency on DAGs like amplitude_subpartitioned.
"""

import argparse
import re
from fnmatch import fnmatch
from glob import glob
from os import path, walk

from bietlejuice.base.dependencies.milestone_strategy_paths import (
    is_milestone_strategy_dir,
)
from bietlejuice.base.paths import DAG_PACKAGES_ROOT

TABLE_MANIFEST_FILENAME = ".table_manifest"
FILENAME_REGEX_PATTERN = r"([a-z0-9_-]+)\.sql"


def _generate_manifest_for_dir(queries_dir: str) -> int:
    """
    Generate .table_manifest in the given directory if it contains .sql files.

    :return: number of table names written to manifest, or 0 if no .sql files
    """
    regex = re.compile(FILENAME_REGEX_PATTERN)
    files = glob(path.join(queries_dir, "*.sql"))
    if not files:
        return 0

    table_names = []
    for file_path in files:
        match = regex.search(file_path)
        if match:
            table_names.append(match.group(1))

    table_names.sort()
    manifest_path = path.join(queries_dir, TABLE_MANIFEST_FILENAME)
    with open(manifest_path, "w") as f:
        f.write("\n".join(table_names))

    return len(table_names)


def generate_query_manifests(dag_name_filter: str = "*") -> int:
    """
    Walk DAG packages and generate .table_manifest for each queries subdir
    that contains .sql files.

    :param dag_name_filter: glob for DAG folder names (e.g. "*" or "amplitude_subpartitioned")
    :return: total number of manifests written
    """
    if not DAG_PACKAGES_ROOT:
        raise RuntimeError(
            "DAG_PACKAGES_ROOT is not set; run from an Airflow/Composer context"
        )

    total = 0
    for root, _dirs, files in walk(DAG_PACKAGES_ROOT):
        # Skip strategy dirs only under milestone_delta (not every nested folder).
        if is_milestone_strategy_dir(root):
            continue
        if "queries" not in root or not any(f.endswith(".sql") for f in files):
            continue
        rel = path.relpath(root, DAG_PACKAGES_ROOT)
        parts = rel.split(path.sep)
        if "queries" in parts and len(parts) >= 3:
            dag_folder = parts[parts.index("queries") - 1]
            if not fnmatch(dag_folder, dag_name_filter):
                continue
        written = _generate_manifest_for_dir(root)
        if written:
            total += 1
            print(f"msg=Wrote manifest, path={root}, table_count={written}\n")
    return total


def main():
    parser = argparse.ArgumentParser(
        description="Generate .table_manifest files for DAG query folders"
    )
    parser.add_argument(
        "-d",
        "--dag_name",
        default="*",
        help="Glob for DAG folder names (default: *)",
    )
    args = parser.parse_args()
    count = generate_query_manifests(dag_name_filter=args.dag_name)
    print(f"msg=Generated manifests, total={count}\n")


if __name__ == "__main__":
    main()
