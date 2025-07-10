import os
from bietlejuice.services.file_service import FileService

from bietlejuice.base.dependencies.bietlejuice_redundant_dependency_finder import (
    BietlejuiceRedundantDependencyFinder,
)

mock_file_path = os.path.join(
    os.path.dirname(os.path.realpath(__file__)), "mock_dependencies.yaml"
)


class TestBietlejuiceRedundantDependencyFinder:
    def test_will_find_all_redundancies_in_mock(self):
        dependencies = FileService.get_dict_from_yaml_file(mock_file_path)
        finder = BietlejuiceRedundantDependencyFinder(dependencies)
        b_redundancies = finder.find_redundant_dependencies("bietlejuice.enrich_b")
        c_redundancies = finder.find_redundant_dependencies("bietlejuice.dw_c")
        e_redundancies = finder.find_redundant_dependencies("bietlejuice.dw_e")

        c_expected_redundancies = [
            "bietlejuice.enrich_a:create-external-table-enrich-table-one"
        ]
        e_expected_redundancies = [
            "bietlejuice.enrich_a:load-enrich-table-one",
            "bietlejuice.enrich_b:load-enrich-table-two",
        ]

        assert not b_redundancies
        assert list(c_redundancies.keys()) == c_expected_redundancies
        assert sorted(list(e_redundancies.keys())) == e_expected_redundancies
