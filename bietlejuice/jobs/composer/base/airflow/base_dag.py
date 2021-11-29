from os import path
from datetime import timedelta
from quintoandar_logger import QuintoAndarLogger

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator

from bietlejuice.jobs.composer.base.airflow.dag_owner_enum import DAGOwnerEnum

logger = QuintoAndarLogger("BaseDAG")
COMPOSER_DAGS_PATH = path.abspath(path.join(__file__, "../../../dags"))


class BaseDAG:
    # TODO: Keep it until all Composer DAG owners are re-assigned
    DEFAULT_OWNER = "Data Engineering Team"
    OPERATOR_RETRIES = {
        "retries": 3,
        "retry_delay": timedelta(minutes=3),
        "max_retry_delay": timedelta(minutes=3),
    }
    EXECUTION_TIMEOUT = timedelta(hours=2)

    @staticmethod
    def build_dag(
        dag_id,
        start_date,
        schedule_interval,
        description="",
        wait_for_downstream=False,
        depends_on_past=False,
        catchup=False,
        orientation="LR",
    ):
        return DAG(
            dag_id=dag_id,
            description=description,
            default_args={
                "owner": DAGOwnerEnum.DEFAULT_OWNER,
                "wait_for_downstream": wait_for_downstream,
                "depends_on_past": depends_on_past,
            },
            start_date=start_date,
            schedule_interval=schedule_interval,
            max_active_runs=1,
            catchup=catchup,
            orientation=orientation,
        )

    @staticmethod
    def build_python_operator(
        task_id,
        python_callable,
        dag,
        op_kwargs=None,
        provide_context=False,
        execution_timeout=EXECUTION_TIMEOUT,
        retries=OPERATOR_RETRIES["retries"],
        retry_delay=OPERATOR_RETRIES["retry_delay"],
        max_retry_delay=OPERATOR_RETRIES["max_retry_delay"],
    ):
        return PythonOperator(
            dag=dag,
            task_id=task_id,
            python_callable=python_callable,
            op_kwargs=op_kwargs,
            provide_context=provide_context,
            execution_timeout=execution_timeout,
            retries=retries,
            retry_delay=retry_delay,
            max_retry_delay=max_retry_delay,
        )

    @staticmethod
    def set_dependencies_in_sequence(sequence_list, from_list, to_list):
        for item in sequence_list:
            from_list[item].set_downstream(to_list[item])

    @staticmethod
    def cross_downstream(from_tasks, to_tasks):
        for task in from_tasks:
            task.set_downstream(to_tasks)

    @staticmethod
    def get_dag_doc(dag_name):
        doc_md_string = ""
        try:
            doc_md_string = open(
                f"{COMPOSER_DAGS_PATH}/{dag_name}/{dag_name}.md"
            ).read()
        except Exception as e:
            logger.info(
                f"m=get_dag_doc, msg=no documentation file found for {dag_name}, e={e}"
            )
        finally:
            return doc_md_string
