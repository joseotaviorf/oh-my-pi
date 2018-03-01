from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from airflow.operators.quintoandar import QuintoAndarPythonOperator
from airflow.operators.subdag_operator import SubDagOperator
from jobs.dags.util import environment as env


class BaseDAG(object):
    DEFAULT_OWNER = 'Data Team'

    @staticmethod
    def build_dag(dag_id, start_date, schedule_interval, description='', wait_for_downstream=False,
                  depends_on_past=False, catchup=False):
        return DAG(
            dag_id=dag_id,
            description=description,
            default_args={
                'owner': BaseDAG.DEFAULT_OWNER,
                'wait_for_downstream': wait_for_downstream,
                'depends_on_past': depends_on_past
            },
            start_date=start_date,
            schedule_interval=schedule_interval,
            max_active_runs=1,
            catchup=catchup
        )

    @staticmethod
    def get_sub_dag_operator(dag, sub_dag_func, sub_dag_name):
        return SubDagOperator(
            subdag=sub_dag_func(sub_dag_name),
            task_id=sub_dag_name,
            dag=dag,
        )

    @staticmethod
    def get_python_operator(task_id, func_command, dag, op_kwargs=None):
        return PythonOperator(
            dag=dag,
            task_id=task_id,
            python_callable=func_command,
            op_kwargs=op_kwargs
        )

    @staticmethod
    def get_sub_dag(main_dag_name, sub_dag_name, schedule_interval, start_date, core_func):
        local_dag = BaseDAG.build_dag(
            '{}.{}'.format(main_dag_name, sub_dag_name),
            schedule_interval=schedule_interval,
            start_date=start_date,
        )

        # injection of the core func code
        core_func(local_dag)

        return local_dag

    @staticmethod
    def get_quintoandar_python_operator(task_id, func_command, dag, op_kwargs=None):
        return QuintoAndarPythonOperator(
            dag=dag,
            task_id=task_id,
            python_callable=func_command,
            op_kwargs=op_kwargs
        )
