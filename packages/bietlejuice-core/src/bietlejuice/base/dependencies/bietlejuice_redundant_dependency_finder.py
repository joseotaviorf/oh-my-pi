from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from bietlejuice.base.dependencies.redundant_dependency_finder import (
    RedundantDependencyFinder,
)


class BietlejuiceRedundantDependencyFinder(RedundantDependencyFinder):
    def normalize(self, dependency_name: str) -> str:
        """Reformats the dependency to <dag-name>:<table-name>"""

        (
            dag_name,
            table_name,
        ) = BietlejuiceDependencyHelper.extract_dag_and_table_from_task_name(
            dependency_name
        )
        if not table_name:
            table_name = dependency_name.split(":")[-1]

        return dag_name + ":" + table_name
