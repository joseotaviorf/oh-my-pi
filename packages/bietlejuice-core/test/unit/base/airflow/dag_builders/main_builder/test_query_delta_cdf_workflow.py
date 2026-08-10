from pathlib import Path


def _base_query_delta_workflow_source() -> str:
    workflow_path = (
        Path(__file__).resolve().parents[7]
        / "bietlejuice-airflow/src/bietlejuice/base/airflow/dag_builders/main_builder/workflows/base_query_delta_workflow.py"
    )
    return workflow_path.read_text()


def _base_query_delta_datazord_workflow_source() -> str:
    workflow_path = (
        Path(__file__).resolve().parents[7]
        / "bietlejuice-airflow/src/bietlejuice/base/airflow/dag_builders/main_builder/workflows/base_query_delta_datazord_workflow.py"
    )
    return workflow_path.read_text()


def test_query_delta_does_not_wire_cdf():
    source = _base_query_delta_workflow_source()

    assert "initialize_cdf_task_creator" not in source
    assert "create_cdf_task_if_configured" not in source
    assert "wire_task_to_sink" not in source


def test_query_delta_datazord_initializes_cdf_task_creator():
    source = _base_query_delta_datazord_workflow_source()

    assert "initialize_cdf_task_creator" in source
    assert "self.load_cdf_to_datazord_task_creator" in source


def test_query_delta_datazord_wires_cdf_after_load_before_downstream_tasks():
    source = _base_query_delta_datazord_workflow_source()

    assert "create_cdf_task_if_configured" in source
    assert "load >> load_cdf_to_datazord_task" in source
    assert "post_load >> register_table" in source
    assert "post_load >> data_quality" in source
    assert "wire_task_to_sink(optimize_delta_tables_task" in source


def test_query_delta_datazord_validation_skips_cdf_via_optimize_none_branch():
    source = _base_query_delta_datazord_workflow_source()

    assert "if not self.is_validation:" in source
    assert "optimize_delta_tables = None" in source
