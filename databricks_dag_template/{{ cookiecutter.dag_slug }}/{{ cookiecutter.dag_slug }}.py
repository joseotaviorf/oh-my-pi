from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base import BaseDAG

DAG_ID = "{{ cookiecutter.dag_slug }}"
ENV = Variable.get("environment")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
{% set tasks = cookiecutter.task_names.replace(' ', '_').replace('-', '_').split(',') %}
{%- for task in tasks %}
{{ task.upper() }}_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/{}/{{ task }}.py".format(ENV, DAG_ID)
)
{%- endfor %}

LOGS_OUTPUT_PATH = "s3://5a-databricks/logs/jobs/{}".format(DAG_ID)

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = []
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime.strptime("{{ cookiecutter.dag_start_date }}", '%Y-%m-%d'),
    schedule_interval="{{ cookiecutter.dag_schedule_interval }}",
    max_active_runs={{ cookiecutter.dag_max_active_runs }},
    catchup={{ cookiecutter.dag_catchup }},
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)
{%- for task in tasks %}
{{ task }}_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="{{ task.replace('_', '-') }}",
    dag=dag,
    json={
        "spark_python_task": {"python_file": {{ task.upper() }}_FILE_PATH},
    },
)
{%- endfor %}
terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

airflow_helpers.chain(
    create_cluster_task,
    {%- for task in tasks %}
    {{ task }}_task,
    {%- endfor %}
    terminate_cluster_task,
)