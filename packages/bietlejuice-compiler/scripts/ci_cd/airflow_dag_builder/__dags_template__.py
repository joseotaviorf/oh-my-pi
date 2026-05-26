"""
airflow parsing enforcement

Note: this line above forces Airflow to parse this file for implemented DAGs
"""

import copy
from os.path import basename, dirname

from airflow.datasets import Dataset

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
    DAGYamlParser,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher import (
    FactoryDispatcher,
)
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.validation.cluster_args import merge_validation_cluster_args

datasets = {datasets}
dag_name = basename(dirname(__file__))
dag_declaration = DAGYamlParser(dag_name=dag_name).dag_declaration()
factory = FactoryDispatcher(
    layer=LayerEnum(dag_declaration["workflow"]["layer"])
).get_factory(
    dag_args=dag_declaration["dag"],
    workflow_args=dag_declaration["workflow"],
    cluster_args=dag_declaration["cluster"],
    dataset_dependencies=datasets,
)
dag = factory.get_workflow().build_dag()

validation = dag_declaration.get("validation")
if validation and validation.get("cluster"):
    validation_factory = FactoryDispatcher(
        layer=LayerEnum(dag_declaration["workflow"]["layer"])
    ).get_factory(
        dag_args=copy.deepcopy(dag_declaration["dag"]),
        workflow_args=copy.deepcopy(dag_declaration["workflow"]),
        cluster_args=merge_validation_cluster_args(
            dag_declaration["cluster"], validation["cluster"]
        ),
        dataset_dependencies=None,
        is_validation=True,
        validation_config=validation,
    )
    validation_dag = validation_factory.get_workflow().build_dag()
