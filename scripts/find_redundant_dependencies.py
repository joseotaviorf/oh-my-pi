import re
import yaml
import argparse
from csv import DictWriter


class RedundantDependencyFinder:
    def __init__(self) -> None:
        self.dependencies = self._generate_dependency_dictionary()

    def find_redundant_dependencies(self, origin_dag: str) -> dict:
        """
        Given a DAG, returns a dictionary in which the keys are its redundant dependencies, and the values are
        lists containing each path that causes the redundancy.
        """

        # Dictionary with the normalized dependencies as keys, and regular dependencies as values
        # The dependencies are normalized because "create-external-table" and "create-table-in-datalake should resolve
        # to the same dependency. However, when printing, we must know the name of the actual dependency."
        original_dependencies = {
            dep["normalized_dependency"]: dep["dependency"]
            for dep in self.dependencies[origin_dag]
        }
        return self._find_redundant_dependencies_recursive(
            original_dependencies, origin_dag
        )

    def _find_redundant_dependencies_recursive(
        self,
        original_dependencies: dict,
        current_dag: str,
        redundancies: dict = None,
        path: list = None,
    ) -> dict:
        """
        Recursively searches for redundant dependencies, saving the paths that cause them.
        """

        is_first_run = False
        if path is None:
            path = []
            redundancies = {}
            is_first_run = True

        for dep in self.dependencies.get(current_dag, []):
            new_path = path + [dep["dependency"]]
            normalized_dependency = dep["normalized_dependency"]
            is_redundancy = (
                not is_first_run and normalized_dependency in original_dependencies
            )

            if is_redundancy:
                redundancy = original_dependencies[normalized_dependency]
                if redundancy not in redundancies:
                    redundancies[redundancy] = []
                redundancies[redundancy].append(new_path)

            self._find_redundant_dependencies_recursive(
                original_dependencies,
                dep["dependency"].split(":")[0],
                redundancies,
                new_path,
            )
        return redundancies

    def _generate_dependency_dictionary(self) -> dict:
        """
        Reads the dependency yaml file and returns a dictionary with this format:

        {
            '<dag-name>': [
                {
                    'dependency': '<exemple-dag>:<load-example-table-into-datalake>',
                    'normalized_dependency': '<example-dag>:<example-table>
                }
            ]
        }

        The normalized dependency aims to extract the table name from the task name. This way, tasks like
        "create-clean-neighborhood-external-table" and "load-clean-neighborhood" will be synonyms.
        """

        dependencies_raw = self._get_dependencies_data_from_yaml()
        dependencies = {}

        for dag in dependencies_raw:
            dependencies[dag] = []
            for dependency in dependencies_raw[dag]:
                dependencies[dag].append(self._create_structured_dependency(dependency))

        return dependencies

    def _get_dependencies_data_from_yaml(self) -> list:
        """This function will return all data in the dependencies yaml file"""

        dependencies_file = "../bietlejuice/jobs/composer/dags/dependencies.yaml"

        with open(dependencies_file, "r") as stream:
            dags = yaml.safe_load(stream)

        return dags

    def _create_structured_dependency(self, dependency_name: str) -> dict:
        """
        Given a dependency name, creates a dictionary with the dependency and the normalized dependency
        (table name extracted from the task name)
        """

        structured_dependency = {"dependency": dependency_name}

        if ":" in dependency_name:
            task_name = dependency_name.split(":")[1]
            dag_name = dependency_name.split(":")[0]
            structured_dependency["normalized_dependency"] = (
                dag_name + ":" + self._extract_table_name_from_task(task_name)
            )
        else:
            structured_dependency["normalized_dependency"] = dependency_name

        return structured_dependency

    def _extract_table_name_from_task(self, task_name: str) -> str:
        """
        Extracts the table name from the task name.
        For example: create-clean-neighborhood-external-table -> neighborhood
        """

        patterns = [
            "load-\w+-(.*)-into-redshift",
            "load-dw-\w+-(.*)",
            "load-\w+-(.*)",
            "create-(?:clean|enrich)-(.*)-external-table",
            "create-(.*)-(?:clean|enrich)-external-table",
            "create-(?:(?:clean|enrich)-)?(.*)-in-datalake",
        ]

        for pattern in patterns:
            match = re.search(pattern, task_name)
            if match:
                return match.group(1)

        return task_name

    @staticmethod
    def print_all_redundancies(redundancies_in_dags: dict, verbosity=1):
        """Prints the the dictionary with this format:
        {
            "<dag>": {
                "<redundant_dependency>": [["first_in_path", "second_in_path"], ["first_in_other_path", "second_in_other_path"]]
            }
        }
        """
        for dag, redundancies in redundancies_in_dags.items():
            print(f"Redundancies for {dag}:")
            RedundantDependencyFinder.print_dag_redundancies(redundancies, verbosity)

    @staticmethod
    def print_dag_redundancies(redundancies: dict, verbosity=1):
        """
        Prints a dictionary of dependencies in the format returned by the method find_redundant_dependencies
        Verbosities:
        1:
            <redundant_dependency> <first_in_path>,<first_in_other_path>
        2:
            <redundant_dependency> is redundant. Satisfied by:
            <first_in_path>
            <first_in_other_path>
        
        3:
            <redundant_dependency> is redundant. Satisfied by:
            - <first_in_path> <- <second_in_path>
            - <first_in_other_path> <- <second_in_other_path>
        """
        for redundancy, paths in redundancies.items():
            if verbosity == 1:
                print(redundancy + " " + str.join(",", {p[0] for p in paths}))
                continue

            print(f"{redundancy} is redundant. Satisfied by:")
            if verbosity == 2:
                for path in {path[0] for path in paths}:
                    print(path)
            else:
                for path in paths:
                    print(f" - {str.join(' <- ', path)}")

            print()

    @staticmethod
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
                RedundantDependencyFinder.write_redundancies_in_dag_to_csv(
                    dag, redundancies_in_dag, writer
                )

    @staticmethod
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

    all_redundancies = {}
    redundancy_finder = RedundantDependencyFinder()
    if args.dag:
        all_redundancies[args.dag] = redundancy_finder.find_redundant_dependencies(
            args.dag
        )
    else:
        for dag in redundancy_finder.dependencies:
            all_redundancies[dag] = redundancy_finder.find_redundant_dependencies(dag)

    if args.verbosity != "0":
        RedundantDependencyFinder.print_all_redundancies(
            all_redundancies, int(args.verbosity)
        )
    if args.csv:
        RedundantDependencyFinder.write_all_redundancies_to_csv(
            all_redundancies, args.csv
        )
