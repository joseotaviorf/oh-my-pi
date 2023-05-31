from airflow.models import DagBag
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import BietlejuiceDependencyHelper

def validate_dependencies_exist(dependencies: dict, dag_bag: DagBag):
    for dependent_name, dependency_list in dependencies.items():
        if dependent_name not in dag_bag.dags:
            print(f"DAG {dependent_name} not found")
            
        for dependency in dependency_list:
            dag_name, task_name = dependency.split(':')
            if dag_name not in dag_bag.dags:
                print(f"DAG {dag_name} not found")
                continue
            if task_name not in dag_bag.dags[dag_name].task_ids:
                print(f"Task {task_name} not found in DAG {dag_name}")
                continue

if __name__ == '__main__':
    dag_bag = DagBag(store_serialized_dags=True, include_examples=False)
    dag_bag.collect_dags_from_db()

    dependencies = BietlejuiceDependencyHelper.read_dependencies()
    validate_dependencies_exist(dependencies, dag_bag)
