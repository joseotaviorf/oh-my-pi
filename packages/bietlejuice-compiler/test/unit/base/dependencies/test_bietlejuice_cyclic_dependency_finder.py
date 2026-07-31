from bietlejuice.base.dependencies.bietlejuice_cyclic_dependency_finder import (
    BietlejuiceCyclicDependencyFinder,
)


class TestBietlejuiceCyclicDependencyFinder:
    def test_will_find_all_cycles(self):
        dependencies = {
            "b": ["a:task_1"],
            "c": ["b:task_2"],
            "a": ["c:task_3"],
            "f": ["e:task_4"],
            "g": ["e:task_4", "f:task_5"],
        }

        found_cycles = BietlejuiceCyclicDependencyFinder.find_all_cyclic_dependencies(
            dependencies
        )
        expected_cycles = {"b": ["a:task_1"], "c": ["b:task_2"], "a": ["c:task_3"]}
        assert found_cycles == expected_cycles

    def test_will_not_fail_on_dags_that_only_appear_as_dependencies(self):
        # "e" is not a key of the dictionary, but it is still a vertex of the graph.
        dependencies = {"b": ["a:task_1"], "a": ["b:task_2", "e:task_3"]}

        assert BietlejuiceCyclicDependencyFinder.find_all_cyclic_dependencies(
            dependencies
        ) == {"b": ["a:task_1"], "a": ["b:task_2"]}

    def test_will_group_cyclic_dependencies_by_cycle(self):
        dependencies = {
            "b": ["a:task_1"],
            "a": ["b:task_2"],
            "d": ["c:task_3"],
            "c": ["d:task_4"],
            "f": ["e:task_5"],
        }

        found_cycles = (
            BietlejuiceCyclicDependencyFinder.find_cyclic_dependencies_by_cycle(
                dependencies
            )
        )

        assert len(found_cycles) == 2
        assert {"a": ["b:task_2"], "b": ["a:task_1"]} in found_cycles
        assert {"c": ["d:task_4"], "d": ["c:task_3"]} in found_cycles

    def test_will_group_no_cycles_when_the_graph_is_acyclic(self):
        dependencies = {"f": ["e:task_4"], "g": ["e:task_4", "f:task_5"]}

        assert (
            BietlejuiceCyclicDependencyFinder.find_cyclic_dependencies_by_cycle(
                dependencies
            )
            == []
        )
