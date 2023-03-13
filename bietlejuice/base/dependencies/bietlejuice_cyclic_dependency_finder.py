class BietlejuiceCyclicDependencyFinder:
    """Class responsible for finding cycles in bietlejuice dependencies."""

    @staticmethod
    def find_all_cyclic_dependencies(dependencies: dict) -> dict:
        """
        Given a dictionary in which each key is a dependent and its value is a list of dependencies,
        return a dictionary in the same format but containing only dependencies that cause cycles

        :param dependencies: Dictionary containing the dependency configuration: keys are DAGs, and values are lists of task dependencies
        :return: Dictionary containing only the cyclic dependencies, in the same format as the input dictionary
        """

        cyclic_dependencies = {}
        for dag in dependencies:
            BietlejuiceCyclicDependencyFinder._find_cycles_in_dag(
                dependencies, dag, cyclic_dependencies
            )
        return cyclic_dependencies

    @staticmethod
    def _find_cycles_in_dag(
        dependencies: dict,
        dag: str,
        cyclic_dependencies: dict,
        dependency_path: list = None,
    ) -> None:
        """
        Given the dependencies dictionary, the current dag being evaluated, the dictionary with dependencies that have
        already been identified as cyclic and the path so far, adds cyclic dependencies to the existing dictionary.

        :param dependencies: Dictionary containing the dependency configuration: keys are DAGs, and values are lists of task dependencies
        :param dag: Name of the DAG currently being evaluated to identify cycles
        :param cyclic_dependencies: Dictionary containing all previously identified cyclic dependencies
        :param dependency_path: Path from the beginning of the evaluation until getting to this DAG. This is important to identify cycles.
        For example, if the recursion went from DAG A, to B, to C, and then again to A, the path will be ["A", "B", "C"], and the reappearance of "A"
        means a cycle has been found.
        """

        dependency_path = dependency_path or [dag]
        for dependency in dependencies.get(dag, []):
            dependency_dag = dependency.split(":")[0]
            is_dependency_already_cyclic = (
                dependency_dag in cyclic_dependencies
                and dependency in cyclic_dependencies[dependency_dag]
            )

            if is_dependency_already_cyclic:
                continue
            if dependency_dag in dependency_path:
                if dag not in cyclic_dependencies:
                    cyclic_dependencies[dag] = []
                if dependency not in cyclic_dependencies[dag]:
                    cyclic_dependencies[dag].append(dependency)
            else:
                BietlejuiceCyclicDependencyFinder._find_cycles_in_dag(
                    dependencies,
                    dependency_dag,
                    cyclic_dependencies,
                    dependency_path + [dependency_dag],
                )
