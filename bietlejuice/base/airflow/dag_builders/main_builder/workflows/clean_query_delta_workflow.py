from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_query_delta_workflow import (
    BaseQueryDeltaWorkflow,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class CleanQueryDeltaWorkflow(BaseQueryDeltaWorkflow):
    """
    Inherits the dag build base to define the flow that creates Delta tables from sql files, in the clean Layer.
    It skips the raw layer completely.

    This workflow is only to be used in very rare and exception cases with the following conditions:
    - The raw data is easily recoverable from the source. For example, it is already in S3.
    - The data is very heavy, and we want to avoid replicating it too much.
    Otherwise, please use the RawCustomIngestion workflow.

    :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
    :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
    :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
    """

    def __init__(self, dag_args, workflow_args, cluster_args):
        super().__init__(dag_args, workflow_args, cluster_args, LayerEnum.CLEAN)
