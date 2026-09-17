"""query_delta spark jobs receive the load window declared in extra_query_template_params."""

from unittest.mock import MagicMock, patch

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.enrich_query_delta_workflow import (
    EnrichQueryDeltaWorkflow,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum

DECLARED_START = "{{ get_date_param(dag_run, macros.ds_add(data_interval_start | ds, -2), 'load_start_date') }}"
DECLARED_END = "{{ get_date_param(dag_run, macros.ds_add(data_interval_start | ds, 1), 'load_end_date') }}"


def _workflow() -> EnrichQueryDeltaWorkflow:
    workflow_args = {
        "type": "query_delta",
        "layer": "enrich",
        "custom_schema": "emr_health",
        "default_extraction_type": "incremental",
        "has_hive_sync": False,
        "extra_query_template_params": {
            "load_start_date": DECLARED_START,
            "load_end_date": DECLARED_END,
        },
        "tables_customization": {
            "daily_emr_cluster_health": {
                "load_spark_job": "load_daily_emr_cluster_health",
                "spark_job_arguments": ["{load_start_date}", "{load_end_date}"],
            }
        },
    }
    with patch.dict("os.environ", {"ENVIRONMENT": "forno"}):
        workflow = EnrichQueryDeltaWorkflow(
            {"name": "enrich_emr_health", "owner": "Data Life Cycle"},
            workflow_args,
            {
                "type": "consolidation_m_general_cluster",
                "databricks_conn_id": "databricks_new_env",
            },
        )
    workflow.config_service = MagicMock()
    workflow.config_service.get_config.return_value = "config"
    workflow._get_tables = lambda: [
        TableAttributes(
            workflow.dag_args,
            workflow.workflow_args,
            LayerEnum.ENRICH,
            "daily_emr_cluster_health",
        )
    ]
    return workflow


def test_custom_load_task_creator_receives_the_declared_window():
    workflow = _workflow()

    with (
        patch.object(workflow, "_create_all_tasks_for_cluster"),
        patch.object(workflow, "_get_dag_documentation", return_value="doc"),
    ):
        workflow.build_dag()

    context = workflow.load_custom_task_creator.dag_execution_context
    assert (context.load_start_date, context.load_end_date) == (
        DECLARED_START,
        DECLARED_END,
    )
