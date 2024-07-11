from dataclasses import dataclass
from airflow.models import DAG
from bietlejuice.base.pipeline import EnvironmentEnum


@dataclass
class DagExecutionContext:
    dag: DAG
    environment: str
    bucket: str
    base_spark_jobs_path: str
    dag_args: dict
    workflow_args: dict
    cluster_args: dict
    load_start_date: str = "{{ get_date_param(dag_run, ds, 'load_start_date') }}"
    load_end_date: str = "{{ get_date_param(dag_run, ds, 'load_end_date') }}"
    execution_date: str = "{{ ds }}"
    incoming_bucket: str = None

    def __post_init__(self):
        assert self.dag is not None, "DAG is required"
        assert self.environment is not None, "Environment is required"
        EnvironmentEnum.validate_env(self.environment)
        assert self.bucket is not None, "Bucket is required"
        assert self.base_spark_jobs_path is not None, "Base Spark Jobs Path is required"
        assert self.dag_args is not None, "DAG Args is required"
        assert self.workflow_args is not None, "Workflow Args is required"
        assert self.cluster_args is not None, "Cluster Args is required"
