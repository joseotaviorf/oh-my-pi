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
    start_date: str = "{{ ds }}"
    end_date: str = "{{ ds }}"
    execution_date: str = "{{ ds }}"

    def __post_init__(self):
        assert self.dag is not None, "DAG is required"
        assert self.environment is not None, "Environment is required"
        EnvironmentEnum.validate_env(self.environment)
        assert self.bucket is not None, "Bucket is required"
        assert self.base_spark_jobs_path is not None, "Base Spark Jobs Path is required"
        assert self.dag_args is not None, "DAG Args is required"
        assert self.workflow_args is not None, "Workflow Args is required"
        assert self.cluster_args is not None, "Cluster Args is required"
