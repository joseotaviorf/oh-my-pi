"""
airflow parsing enforcement

Note: this line above forces Airflow to parse this file for implemented DAGs
"""

from os.path import basename, dirname

from airflow.datasets import Dataset

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
    DAGYamlParser,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher import (
    FactoryDispatcher,
)
from bietlejuice.base.pipeline import LayerEnum

datasets = {datasets}
priority_tier = {priority_tier}
dag_name = basename(dirname(__file__))
dag_declaration = DAGYamlParser(dag_name=dag_name).dag_declaration()
factory = FactoryDispatcher(
    layer=LayerEnum(dag_declaration["workflow"]["layer"])
).get_factory(
    dag_args=dict(dag_declaration["dag"], priority_tier=priority_tier),
    workflow_args=dag_declaration["workflow"],
    cluster_args=dag_declaration["cluster"],
    dataset_dependencies=datasets,
)
dag = factory.get_workflow().build_dag()
