from typing import List, Tuple, Set
from collections import defaultdict


class BietlejuiceCyclicDependencyFinder:
    """Class responsible for finding cycles in bietlejuice dependencies."""

    @classmethod
    def find_all_cyclic_dependencies(cls, dependencies: dict) -> dict:
        """
        Given a dictionary in which each key is a dependent and its value is a list of dependencies,
        return a dictionary in the same format but containing only dependencies that cause cycles

        :param dependencies: Dictionary containing the dependency configuration: keys are DAGs, and values are lists of task dependencies
        :return: Dictionary containing only the cyclic dependencies, in the same format as the input dictionary
        """

        cyclic_dependencies = defaultdict(list)

        # A strongly connected component is a set of nodes in a directed graph that are all reachable from each other
        # If there is more than one node in a strongly connected component, there is a cycle
        # We are marking every dependency that connects DAGs in the same component as cyclic
        strongly_connected_components = cls._find_strongly_connected_components(
            dependencies
        )
        for component in strongly_connected_components:
            if len(component) <= 1:
                continue
            for dag in component:
                for dependency in dependencies[dag]:
                    dependency_dag = dependency.split(":")[0]
                    if dependency_dag in component:
                        cyclic_dependencies[dag].append(dependency)
        return cyclic_dependencies

    @classmethod
    def _find_strongly_connected_components(cls, dependencies: dict) -> List[Set[str]]:
        """
        Uses [Kosaraju's algorithm](https://en.wikipedia.org/wiki/Kosaraju%27s_algorithm) to find the strongly connected components in a graph

        1 - We perform a DFS on the original graph and record the order in which we finish visiting each vertex
        2 - We transpose the graph (revert all the edges)
        3 - We perform a DFS on the transposed graph, following the reverse order of the finish times from the first DFS

        Each DFS will find a strongly connected component.
        """

        graph, dags = cls._create_graph(dependencies)
        finish_order = cls._dfs(graph)
        transposed_graph = cls._transpose_graph(graph)
        strongly_connected_components = cls._dfs_to_find_components(
            transposed_graph, finish_order[::-1]
        )
        return [
            {dags[vertex] for vertex in component}
            for component in strongly_connected_components
        ]

    @staticmethod
    def _create_graph(dependencies: dict) -> Tuple[List[List[int]], List[str]]:
        """
        Returns a tuple containing
        - The adjacency lists of the graph
            - Each edge in the adjacency list has the index of the next vertex and also the full name of the dependency
        - A list of DAGs in the same order as the adjacency list
        """
        dags = []
        dag_indexes = {}
        graph = []

        def get_dag_index(dag_name: str) -> int:
            if dag_name not in dag_indexes:
                dag_indexes[dag_name] = len(dag_indexes)
                dags.append(dag_name)
                graph.append([])
            return dag_indexes[dag_name]

        for dependent_dag, dependencies_list in dependencies.items():
            dependent_dag_index = get_dag_index(dependent_dag)
            for dependency in dependencies_list:
                dependency_dag = dependency.split(":")[0]
                dependency_dag_index = get_dag_index(dependency_dag)
                graph[dependent_dag_index].append(dependency_dag_index)

        return graph, dags

    @classmethod
    def _dfs(cls, graph: List[List[Tuple[int, str]]]) -> List[int]:
        """Runs a Depth-First-Search(DFS) on the graph and returns the order in which the vertices were finished"""

        visited = [False] * len(graph)
        stack = []
        for vertex in range(len(graph)):
            if not visited[vertex]:
                cls._dfs_rec(graph, vertex, visited, stack)
        return stack

    @classmethod
    def _dfs_rec(
        cls, graph: List[List[int]], vertex: int, visited: List[bool], stack: List[int]
    ) -> None:
        """Auxiliary function to run the DFS recursively"""

        visited[vertex] = True
        for neighbor in graph[vertex]:
            if not visited[neighbor]:
                cls._dfs_rec(graph, neighbor, visited, stack)
        stack.append(vertex)

    @staticmethod
    def _transpose_graph(graph: List[List[int]]) -> List[List[int]]:
        """Reverts all the edges in the graph"""

        transposed_graph = [[] for _ in range(len(graph))]
        for vertex, neighbors in enumerate(graph):
            for neighbor in neighbors:
                transposed_graph[neighbor].append(vertex)
        return transposed_graph

    @classmethod
    def _dfs_to_find_components(
        cls, graph: List[List[int]], order: List[int]
    ) -> List[List[int]]:
        """
        Runs a DFS on the transposed graph following the provided order. Returns each DFS result separately.
        Each result is a strongly connected component.
        """

        visited = [False] * len(graph)
        components = []
        for vertex in order:
            stack = []
            if not visited[vertex]:
                cls._dfs_rec(graph, vertex, visited, stack)
            components.append(stack)
        return components
