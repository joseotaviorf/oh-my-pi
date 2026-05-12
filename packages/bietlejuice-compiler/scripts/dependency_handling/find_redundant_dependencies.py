import argparse
from csv import DictWriter
import os
import sys

BI_ETL_EJUICE_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
sys.path.append(BI_ETL_EJUICE_ROOT)

from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from bietlejuice.base.dependencies.bietlejuice_redundant_dependency_finder import (
    BietlejuiceRedundantDependencyFinder,
)


def print_all_redundancies(redundancies_in_dags: dict, verbosity=1):
    """Prints the the dictionary with the format:
    {
        "<de>": {
            "<redundant_dependency>": [["first_in_path", "second_in_path"], ["first_in_other_path", "second_in_other_path"]]
        }
    }
    """
    for dag, redundancies in redundancies_in_dags.items():
        if not redundancies:
            continue

        print(f"Redundancies for {dag}:")
        print(
            BietlejuiceRedundantDependencyFinder.format_redundancies(
                redundancies, verbosity
            )
        )


def write_all_redundancies_to_csv(all_redundancies: dict, path: str):
    """
    Writes a dictionary into a CSV file in the given path.
    The keys are DAGs and the values are redundancies
    """

    with open(path, "w+") as stream:
        field_names = ["DAG", "Redundant Dependency", "Satisfied By"]
        writer = DictWriter(stream, fieldnames=field_names)
        writer.writeheader()
        for dag, redundancies_in_dag in all_redundancies.items():
            write_redundancies_in_dag_to_csv(dag, redundancies_in_dag, writer)


def write_redundancies_in_dag_to_csv(
    dag: str, redundancies_in_dag: dict, writer: DictWriter
):
    """
    Writes a dictionary into a CSV file using the given DictWriter.
    The keys are redundancies and the values are lists of lists containing the paths that satisfy it.
    """
    for redundancy, paths in redundancies_in_dag.items():
        for path in paths:
            formatted_path = " <- ".join(path)
            writer.writerow(
                {
                    "DAG": dag,
                    "Redundant Dependency": redundancy,
                    "Satisfied By": formatted_path,
                }
            )


if __name__ == "__main__":
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument(
        "--dag",
        "-d",
        required=False,
        help="Name of the DAG to check redundancies. If not specified, will check all DAGs.",
    )
    arg_parser.add_argument(
        "--verbosity",
        "-v",
        required=False,
        help="Level of verbosity between 0 and 3. Determines how the redundancies will be printed on the console",
        default=1,
    )
    arg_parser.add_argument(
        "--csv",
        "-c",
        required=False,
        help="Path to the csv file where the redundancies will be written",
    )

    args = arg_parser.parse_args()
    dag = args.dag
    verbosity = int(args.verbosity)
    csv_file = args.csv

    dependencies = BietlejuiceDependencyHelper.read_dependencies()
    redundancy_finder = BietlejuiceRedundantDependencyFinder(dependencies)

    all_redundancies = {}
    if dag:
        all_redundancies[dag] = redundancy_finder.find_redundant_dependencies(dag)
    else:
        for dag in redundancy_finder.dependencies:
            all_redundancies[dag] = redundancy_finder.find_redundant_dependencies(dag)

    if verbosity != 0:
        print_all_redundancies(all_redundancies, verbosity)
    if csv_file:
        write_all_redundancies_to_csv(all_redundancies, csv_file)
