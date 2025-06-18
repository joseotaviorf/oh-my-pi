from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)


class RedundantDependencyFinder:
    def __init__(self, dependencies_raw: dict) -> None:
        """
        :param dependencies_raw: Dictionary containing dependencies. The key is a dependent, and the value is a list of dependencies.
        """
        self.dependencies_raw = dependencies_raw
        self.dependencies = self._normalize_all_dependencies(dependencies_raw)

    def remove_all_redundancies(self) -> dict:
        """Removes all the redundant dependencies from the dictionary, and returns a new one"""
        new_dependencies = {}

        for dag in self.dependencies_raw:
            redundancies = self.find_redundant_dependencies(dag)
            new_dependencies[dag] = list(
                self.dependencies_raw[dag] - redundancies.keys()
            )

        return new_dependencies

    def find_redundant_dependencies(self, origin_dependent: str) -> dict:
        """
        Given a dependent, returns a dictionary in which the keys are its redundant dependencies, and the values are
        lists containing each path that causes the redundancy.
        """

        # Dictionary with the normalized dependencies as keys, and regular dependencies as values
        normalized_dependencies_from_origin = {
            dep["normalized_dependency"]: dep["dependency"]
            for dep in self.dependencies[origin_dependent]
        }
        return self._find_redundant_dependencies_recursive(
            normalized_dependencies_from_origin, origin_dependent
        )

    def _find_redundant_dependencies_recursive(
        self,
        normalized_dependencies_from_origin: dict,
        current_dependent: str,
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

        for dep in self.dependencies.get(current_dependent, []):
            new_path = path + [dep["dependency"]]
            normalized_dependency = dep["normalized_dependency"]
            is_redundancy = (
                not is_first_run
                and normalized_dependency in normalized_dependencies_from_origin
            )

            if is_redundancy:
                denormalized_dependency = normalized_dependencies_from_origin[
                    normalized_dependency
                ]
                if denormalized_dependency not in redundancies:
                    redundancies[denormalized_dependency] = []
                redundancies[denormalized_dependency].append(new_path)

            self._find_redundant_dependencies_recursive(
                normalized_dependencies_from_origin,
                dep["dependency"].split(":")[0],
                redundancies,
                new_path,
            )
        return redundancies

    def _normalize_all_dependencies(self, dependencies_raw: dict) -> dict:
        """
        Uses self.dependencies_raw dictionary, and returns a dictionary with this format:

        {
            '<dependent-name>': [
                {
                    'dependency': '<dependency>',
                    'normalized_dependency': '<normalized-dependency>
                }
            ]
        }

        The normalized dependency is what will actually be compared to determine if two dependencies are redundant.
        """

        dependencies = {}

        for dependent in dependencies_raw:
            dependencies[dependent] = []
            flat_dependencies = BietlejuiceDependencyHelper.find_unique_dependencies_in_dependency_object(
                dependencies_raw[dependent]
            )
            for dependency in flat_dependencies:
                dependencies[dependent].append(
                    self._create_structured_dependency(dependency)
                )

        return dependencies

    def _create_structured_dependency(self, dependency_name: str) -> dict:
        """
        Given a dependency name, creates a dictionary with the dependency and the normalized dependency
        """

        structured_dependency = {
            "dependency": dependency_name,
            "normalized_dependency": self.normalize(dependency_name),
        }

        return structured_dependency

    def normalize(self, dependency_name: str) -> str:
        """
        Returns the dependency_name by default, but can be overwritten to take any normalizing behavior.
        This allows one to consider two similar names as redundant.
        For example, if "do-task-a" and "execute-task-a-completely" should be synonyms, "a" could be the normalized dependency.
        """
        return dependency_name

    @staticmethod
    def format_redundancies(redundancies: dict, verbosity=1):
        """
        Formats a dictionary of dependencies in the format returned by the method find_redundant_dependencies
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
        formatted_dependencies = ""

        for redundancy, paths in redundancies.items():
            if verbosity == 1:
                formatted_dependencies += (
                    redundancy + " " + str.join(",", {p[0] for p in paths}) + "\n"
                )
                continue

            formatted_dependencies += f"{redundancy} is redundant. Satisfied by:\n"
            if verbosity == 2:
                for path in {path[0] for path in paths}:
                    formatted_dependencies += path + "\n"
            else:
                for path in paths:
                    formatted_dependencies += f" - {str.join(' <- ', path)}\n"

            formatted_dependencies += "\n"

        return formatted_dependencies
