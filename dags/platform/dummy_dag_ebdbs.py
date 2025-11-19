from __future__ import annotations

import pendulum

from airflow.models.dag import DAG
from airflow.datasets import Dataset
from airflow.operators.bash import BashOperator

# 1. Define the Dataset
# This is the unique identifier that other DAGs can subscribe to.
# The URI format is airflow://<host>/<path> (the host/path is arbitrary, 
# but should be descriptive and unique, often mirroring a path or system).
MY_OUTPUT_DATASET = Dataset("bietlejuice.dummy_dag_ebdbs:load-ebdb:reprocessing")

with DAG(
    dag_id="bietlejuice.dummy_dag_ebdbs",
    start_date=pendulum.datetime(2025, 1, 1, tz="UTC"),
    schedule=None,  # This DAG runs manually or by a traditional schedule (not dataset-triggered)
    catchup=False,
    tags=["dataset", "example", "producer"],
    doc_md=__doc__,
) as dag:
    
    # 2. The task that produces the data and emits the event
    # By setting 'outlets=[MY_OUTPUT_DATASET]', Airflow knows this task 
    # produces data for this specific Dataset. When the task succeeds, 
    # Airflow automatically records a Dataset update event.
    
    process_data_task = BashOperator(
        task_id="process_and_upload_sales_data",
        bash_command=(
            "echo 'Simulating data processing and upload...';"
            "sleep 5;" # Simulate work
            "echo 'Dataset event for s3://my-data-bucket/processed_sales_data_2025.csv emitted!'"
        ),
        outlets=[MY_OUTPUT_DATASET],  # <-- **This is the key line for emitting the event**
    )

    # 3. Optional downstream task (for illustration)
    notify_completion_task = BashOperator(
        task_id="notify_completion",
        bash_command="echo 'Producer DAG complete. Check the Airflow UI for the Dataset event.'",
    )

    process_data_task >> notify_completion_task