import os

from bietlejuice.jobs.composer.base.airflow.base_dag import BaseDAG
from bietlejuice.jobs.composer.base.airflow.base_dag import BaseDAG
from bietlejuice.jobs.composer.base.airflow.base_sub_dag import BaseSubDAG
from bietlejuice.jobs.composer.base.airflow.base_sub_dag import BaseSubDAG
from bietlejuice.jobs.composer.base.airflow.environment import Environment
from bietlejuice.jobs.composer.base.airflow.environment import Environment

DEPENDENCIES_FILE_PATH = os.path.join(
    os.path.dirname(os.path.realpath(__file__)), "../../dags/dependencies.yml"
)
