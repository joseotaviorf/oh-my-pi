from pathlib import Path


def test_wonka_workflow_preserves_validation_dag_id_suffix():
    wonka_workflow_path = (
        Path(__file__).resolve().parents[6]
        / "src/bietlejuice/base/airflow/dag_builders/main_builder/workflows/wonka_workflow.py"
    )
    source = wonka_workflow_path.read_text()

    assert 'wonka_dag_id = f"quintoml.wonka.{self.dag_name.replace' in source
    assert "if self.is_validation:" in source
    assert 'self.dag_id = f"{wonka_dag_id}{self.VALIDATION_DAG_SUFFIX}"' in source
