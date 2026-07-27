"""
airflow parsing enforcement

Note: this line above forces Airflow to parse this file for implemented DAGs
"""

from os.path import basename, dirname

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
    DAGYamlParser,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher import (
    FactoryDispatcher,
)
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.validation.cluster_args import merge_validation_cluster_args

dag_name = basename(dirname(__file__))
dag_declaration = DAGYamlParser(dag_name=dag_name).dag_declaration()
validation = dag_declaration.get("validation") or {}
if not validation.get("cluster"):
    raise RuntimeError(
        f"Generated validation DAG for {dag_name} but declaration has no "
        "validation.cluster — regenerate with create-dag-files"
    )

validation_factory = FactoryDispatcher(
    layer=LayerEnum(dag_declaration["workflow"]["layer"])
).get_factory(
    dag_args=dag_declaration["dag"],
    workflow_args=dag_declaration["workflow"],
    cluster_args=merge_validation_cluster_args(
        dag_declaration["cluster"], validation["cluster"]
    ),
    dataset_dependencies=None,
    is_validation=True,
    validation_config=validation,
)
validation_dag = validation_factory.get_workflow().build_dag()
