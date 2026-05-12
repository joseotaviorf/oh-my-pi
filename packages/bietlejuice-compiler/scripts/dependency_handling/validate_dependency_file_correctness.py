from collections import defaultdict
from scripts.dependency_handling.automate_dependencies import generate_dependencies
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)


def main():
    print("Generating expected dependency file...")
    expected_dependencies_file = generate_dependencies()
    print("Expected dependency file generated. Comparing with existing file...")
    existing_dependencies_file = BietlejuiceDependencyHelper.read_dependencies()
    differences = compare_dependencies(
        expected_dependencies_file, existing_dependencies_file
    )
    if differences:
        print("Differences were found between the committed and the expected versions of 'dependencies.yaml'.")
        print_differences(differences)
        print("Run locally the following command to generate a valid version:\n\n"
              "make dependencies-file\n\n"
              "If the current committed version has to be considered correct, add the differences as exceptions in one of the following files:\n"
              "\t- 'dags/dependency_exceptions/unstandard_dags.yaml' for DAGs out of standard;\n"
              "\t- 'dags/dependency_exceptions/manual_modifications.yaml' for manual task IDs modifications.")
        return 1
    else:
        print("dependencies.yaml file is correct")
        return 0


def compare_dependencies(
    expected_dependencies_file: dict, existing_dependencies_file: dict
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
    """
    differences = defaultdict(dict)
    for dag_name, dependency_list in expected_dependencies_file.items():
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
        if dag_name not in expected_dependencies_file:
            differences[dag_name]["extra"] = existing_dependencies_file[dag_name]

    return differences


def print_differences(differences: dict):
    for dag_name, difference in differences.items():
        print(f"==== Dag {dag_name} has the following differences: ====")
        if "missing" in difference:
            print(f"Missing dependencies:")
            print(" - " + "\n - ".join(difference["missing"]))
        if "extra" in difference:
            print(f"Extra dependencies:")
            print(" - " + "\n - ".join(difference["extra"]))
        print("========================================")


if __name__ == "__main__":
    exit(main())
