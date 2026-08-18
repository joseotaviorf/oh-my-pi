from airflow.datasets import BaseDataset

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_query_delta_datazord_workflow import (
    BaseQueryDeltaDatazordWorkflow,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class EnrichQueryDeltaDatazordWorkflow(BaseQueryDeltaDatazordWorkflow):
    """query_delta_datazord workflow for the enrich layer."""

    def __init__(
        self,
        dag_args,
        workflow_args,
        cluster_args,
        dataset_dependencies: BaseDataset = None,
        **kwargs,
    ):
        layer = LayerEnum(workflow_args.get("layer", LayerEnum.ENRICH.value))
        super().__init__(
            dag_args,
            workflow_args,
            cluster_args,
            layer,
            dataset_dependencies,
            **kwargs,
        )
