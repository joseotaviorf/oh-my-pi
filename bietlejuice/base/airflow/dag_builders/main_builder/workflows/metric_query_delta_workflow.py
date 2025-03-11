from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_query_delta_workflow import (
    BaseQueryDeltaWorkflow,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class MetricQueryDeltaWorkflow(BaseQueryDeltaWorkflow):
    """
    Inherits the dag build base to define the flow that creates Delta tables from sql files, in the metric Layer.
    :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
    :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
    :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
    """

    def __init__(self, dag_args, workflow_args, cluster_args):
        super().__init__(dag_args, workflow_args, cluster_args, LayerEnum.METRIC)
