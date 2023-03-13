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
