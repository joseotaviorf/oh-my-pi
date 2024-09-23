import json
import os
from datetime import datetime, date
from airflow.models import DAG, Variable
from airflow.operators.python_operator import PythonOperator
from pendulum import datetime, timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum


DAG_NAME = "skip_list_cleaner"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2024, 9, 12, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 0 * * *"


def clean_skip_list():
    key = "MEDIATOR_SKIP_LIST"
    previous_skip_list = Variable.get(key)
    today_date = date.today()
    print(
        f"""
            m=clean_skip_list, msg=Cleaning skip list parameters that has date before {today_date},
            skip_list_before_cleaning=
            {previous_skip_list}
        """
    )
    clean_skip_list = json.loads(previous_skip_list)
    clean_skip_list["_last_updater"] = "DAG bietlejuice.skip_list_cleaner"
    if clean_skip_list["dags_not_to_trigger"]:
        for dag_id, skip_date in list(clean_skip_list["dags_not_to_trigger"].items()):
            skip_date = datetime.strptime(skip_date, "%Y-%m-%d").date()
            if skip_date < today_date:
                print(
                    f"m=clean_skip_list, msg=Removing DAG {dag_id} from 'dags_not_to_trigger' because the skip date is too old, skip_date={skip_date}, today_date={today_date}"
                )
                del clean_skip_list["dags_not_to_trigger"][dag_id]

    if clean_skip_list["skip_all_dependents_from_dags"]:
        for dag_id, skip_date in list(
            clean_skip_list["skip_all_dependents_from_dags"].items()
        ):
            skip_date = datetime.strptime(skip_date, "%Y-%m-%d").date()
            if skip_date < today_date:
                print(
                    f"m=clean_skip_list, msg=Removing DAG {dag_id} from 'skip_all_dependents_from_dags' because the skip date is too old, skip_date={skip_date}, today_date={today_date}"
                )
                del clean_skip_list["skip_all_dependents_from_dags"][dag_id]

    Variable.set(key, json.dumps(clean_skip_list, indent=4))


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_INGESTION,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME),
)

delete_jobs_task = PythonOperator(
    task_id=f"clean-skip-list",
    dag=dag,
    python_callable=clean_skip_list,
)
