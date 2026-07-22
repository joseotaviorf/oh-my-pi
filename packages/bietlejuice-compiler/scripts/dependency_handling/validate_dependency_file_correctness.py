import os
from collections import defaultdict

from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from dags import DAG_PACKAGES_ROOT
from scripts.dependency_handling.automate_dependencies import generate_dependencies

_DAG_ID_PREFIX = "bietlejuice."
# Luigi Jr DAGs live under dags/luigijr/. They are scaffolded by Zordon and
# deployed only to dedicated luigijr Astro instances (forno-luigijr / prod
# luigijr), isolated from the main forno/prod DAG bag. Their bot-authored PRs
# only touch dags/luigijr/** and never update the shared dags/dependencies.yaml,
# and they are scheduled independently on their own instance rather than being
# dataset-triggered from upstream DAGs. So the shared dependency file is not
# expected to track them: skip DAGs keyed under this domain when checking
# correctness. Mirrors the path-prefix exception used by
# validate_no_new_databricks_clusters (databricks_cluster_exceptions.yml).
_LUIGIJR_DOMAIN_DIR = "luigijr"


def luigijr_dag_ids(dags_root: str = DAG_PACKAGES_ROOT) -> "frozenset[str]":
    """Return the dependency-file keys (``bietlejuice.<dag>``) for DAGs under dags/luigijr/."""
    luigijr_dir = os.path.join(dags_root, _LUIGIJR_DOMAIN_DIR)
    if not os.path.isdir(luigijr_dir):
        return frozenset()
    return frozenset(
        f"{_DAG_ID_PREFIX}{name}"
        for name in os.listdir(luigijr_dir)
        if os.path.isdir(os.path.join(luigijr_dir, name))
    )


def main():
    print("Generating expected dependency file...")
    expected_dependencies_file = generate_dependencies()
    print("Expected dependency file generated. Comparing with existing file...")
    existing_dependencies_file = BietlejuiceDependencyHelper.read_dependencies()
    ignored_dags = luigijr_dag_ids()
    if ignored_dags:
        print(
            f"Skipping {len(ignored_dags)} Luigi Jr DAG(s) under 'dags/{_LUIGIJR_DOMAIN_DIR}/' "
            "(isolated domain, not tracked in the shared dependencies.yaml)."
        )
    differences = compare_dependencies(
        expected_dependencies_file, existing_dependencies_file, ignored_dags
    )
    if differences:
        print(
            "Differences were found between the committed and the expected versions of 'dependencies.yaml'."
        )
        print_differences(differences)
        print(
            "Run locally the following command to generate a valid version:\n\n"
            "make dependencies-file\n\n"
            "If the current committed version has to be considered correct, add the differences as exceptions in one of the following files:\n"
            "\t- 'dags/dependency_exceptions/unstandard_dags.yaml' for DAGs out of standard;\n"
            "\t- 'dags/dependency_exceptions/manual_modifications.yaml' for manual task IDs modifications."
        )
        return 1
    else:
        print("dependencies.yaml file is correct")
        return 0


def compare_dependencies(
    expected_dependencies_file: dict,
    existing_dependencies_file: dict,
    ignored_dags: "frozenset[str]" = frozenset(),
) -> dict:
    """
    Compares two dependency files and returns a dict of differences
    The dict has the following structure:
    {
        dag_name: {
            "missing": [list of missing dependencies],
            "extra": [list of extra dependencies]
        }
    }

    DAGs whose key is in ``ignored_dags`` are excluded from the comparison
    (used to skip the isolated Luigi Jr domain).
    """
    differences = defaultdict(dict)
    for dag_name, dependency_list in expected_dependencies_file.items():
        if dag_name in ignored_dags:
            continue
        if dag_name not in existing_dependencies_file:
            differences[dag_name]["missing"] = dependency_list
            continue
        existing_dependency_list = existing_dependencies_file[dag_name]
        missing = [
            dependency
            for dependency in dependency_list
            if dependency not in existing_dependency_list
        ]
        extra = [
            dependency
            for dependency in existing_dependency_list
            if dependency not in dependency_list
        ]
        if missing:
            differences[dag_name]["missing"] = missing
        if extra:
            differences[dag_name]["extra"] = extra
    for dag_name in existing_dependencies_file:
        if dag_name in ignored_dags:
            continue
        if dag_name not in expected_dependencies_file:
            differences[dag_name]["extra"] = existing_dependencies_file[dag_name]

    return differences


def print_differences(differences: dict):
    for dag_name, difference in differences.items():
        print(f"==== Dag {dag_name} has the following differences: ====")
        if "missing" in difference:
            print("Missing dependencies:")
            print(" - " + "\n - ".join(difference["missing"]))
        if "extra" in difference:
            print("Extra dependencies:")
            print(" - " + "\n - ".join(difference["extra"]))
        print("========================================")


if __name__ == "__main__":
    exit(main())
