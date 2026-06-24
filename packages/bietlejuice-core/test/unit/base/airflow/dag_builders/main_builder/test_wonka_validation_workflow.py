from pathlib import Path


def _wonka_workflow_source() -> str:
    wonka_workflow_path = (
        Path(__file__).resolve().parents[6]
        / "src/bietlejuice/base/airflow/dag_builders/main_builder/workflows/wonka_workflow.py"
    )
    return wonka_workflow_path.read_text()


def test_wonka_workflow_preserves_validation_dag_id_suffix():
    source = _wonka_workflow_source()

    assert 'wonka_dag_id = f"quintoml.wonka.{self.dag_name.replace' in source
    assert "if self.is_validation:" in source
    assert 'self.dag_id = f"{wonka_dag_id}{self.VALIDATION_DAG_SUFFIX}"' in source


def test_validation_skips_optimize_cdf_and_wires_load_wonka_to_sink():
    source = _wonka_workflow_source()

    assert "if self.is_validation:" in source
    assert (
        "execute_job_cluster_task >> load_wonka_task >> cluster_completion_sink"
        in source
    )
    assert "self.optimize_delta_table_task_creator.create_task" in source
    assert "self.load_cdf_to_datazord_task_creator.create_task" in source


def test_prod_branch_still_creates_optimize_and_cdf():
    source = _wonka_workflow_source()

    validation_block_start = source.index("if self.is_validation:")
    prod_branch = source[validation_block_start:]
    assert "optimize_delta_tables_task" in prod_branch
    assert "load_cdf_to_datazord_task" in prod_branch


def test_validation_merges_wonka_runtime_overlay():
    source = _wonka_workflow_source()

    assert "_wonka_runtime_overlay" in source
    assert "_WONKA_RUNTIME_TOP_LEVEL_KEYS" in source
    assert "install_pex_generic.sh" in source
    assert "runtime_overlay = self._wonka_runtime_overlay" in source
