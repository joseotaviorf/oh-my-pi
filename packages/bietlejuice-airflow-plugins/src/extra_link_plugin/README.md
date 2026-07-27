# DatasetTriggerOperatorLink – Custom Airflow Extra Link

This plugin provides a custom **Extra Link** for Airflow tasks, allowing users to trigger a manual dataset event in the `trigger_datasets` DAG when a task fails or needs to be retriggered manually.

## 🔗 Purpose

The `DatasetTriggerOperatorLink` generates a UI link on specific Airflow task instances, pointing to a form that enables users to manually trigger a dataset event. This is especially useful for **unblocking downstream DAGs or datasets** in case of failures or missed runs.

## 🧠 How It Works

- The link appears as a button labeled **"Trigger Dataset Event"** in the Airflow UI for the task.
- It uses XCom to determine whether the current run is the **first run of the day**, and includes that in the query string.
- It builds a URL with query parameters:
  - `source_dag_id`
  - `source_task_id`
  - `source_run_id`
  - `is_first_run_of_date`


