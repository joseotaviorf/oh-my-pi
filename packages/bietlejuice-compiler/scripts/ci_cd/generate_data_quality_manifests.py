"""
Generate .data_quality_manifest files for DAG data_quality folders to avoid GCS glob at parse time.

Each data_quality/{layer}/ directory containing .yml or .yaml files gets a
.data_quality_manifest file with one table path (relative path without ext) per line.
At parse time, list_data_quality_table_paths_in_composer reads the manifest when present
instead of globbing, reducing latency on DAGs with many data quality files.
"""

import argparse
import os
from fnmatch import fnmatch
from os import path, walk

from bietlejuice.base.paths import DAG_PACKAGES_ROOT

DATA_QUALITY_MANIFEST_FILENAME = ".data_quality_manifest"
DATA_QUALITY_EXTENSIONS = (".yml", ".yaml")


def _generate_data_quality_manifest_for_dir(data_quality_layer_dir: str) -> int:
    """
    Generate .data_quality_manifest in the given data_quality/{layer}/ directory.

    :return: number of table paths written to manifest, or 0 if no data quality files
    """
    table_names = []
    for root, _dirs, files in os.walk(data_quality_layer_dir):
        for f in files:
            if f.lower().endswith(DATA_QUALITY_EXTENSIONS):
                abs_path = path.join(root, f)
                rel = path.relpath(abs_path, data_quality_layer_dir)
                name_without_ext = path.splitext(rel)[0]
                table_names.append(path.normpath(name_without_ext))
    if not table_names:
        return 0
    table_names.sort()
    manifest_path = path.join(data_quality_layer_dir, DATA_QUALITY_MANIFEST_FILENAME)
    with open(manifest_path, "w") as fp:
        fp.write("\n".join(table_names))
    return len(table_names)


def generate_data_quality_manifests(dag_name_filter: str = "*") -> int:
    """
    Walk DAG packages and generate .data_quality_manifest for each data_quality/{layer} subdir.

    :param dag_name_filter: glob for DAG folder names (e.g. "*" or "amplitude_subpartitioned")
    :return: total number of manifests written
    """
    if not DAG_PACKAGES_ROOT:
        raise RuntimeError(
            "DAG_PACKAGES_ROOT is not set; run from an Airflow/Composer context"
        )

    total = 0
    for root, _dirs, _files in walk(DAG_PACKAGES_ROOT):
        rel = path.relpath(root, DAG_PACKAGES_ROOT)
        parts = rel.split(path.sep)
        # Process only <domain>/<dag>/data_quality/<layer>. Nested table paths
        # are included recursively by _generate_data_quality_manifest_for_dir.
        if len(parts) != 4 or parts[2] != "data_quality":
            continue
        dag_folder = parts[1]
        if not fnmatch(dag_folder, dag_name_filter):
            continue
        written = _generate_data_quality_manifest_for_dir(root)
        if written:
            total += 1
            print(
                f"msg=Wrote data quality manifest, path={root}, table_count={written}\n"
            )
    return total


def main():
    parser = argparse.ArgumentParser(
        description="Generate .data_quality_manifest files for DAG data_quality folders"
    )
    parser.add_argument(
        "-d",
        "--dag_name",
        default="*",
        help="Glob for DAG folder names (default: *)",
    )
    args = parser.parse_args()
    count = generate_data_quality_manifests(dag_name_filter=args.dag_name)
    print(f"msg=Generated data quality manifests, total={count}\n")


if __name__ == "__main__":
    main()
