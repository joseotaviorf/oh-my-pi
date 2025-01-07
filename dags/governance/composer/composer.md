## Composer

### Purpose

Dumps the Composer Airflow database into S3. To know more about airflow's tables
take a look [here](https://www.astronomer.io/guides/airflow-database).

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We are not dumping all Airflow tables. This currently produces the following output tables in the raw layer:

 - `dag` - Information about the DAG
 - `dag_run` - DAG runs historic
 - `log` - Information about task events. This table can be used as an aud (like event, ts_event (dttm), etc)
 - `task_fail` - Information about failed tasks (subset of Airflow task_instances table)
 - `task_instance` - Information about the task run (like duration, try_numbers, etc)
 - `serialized_dag` - Snapshot of DAG files synchronized by scheduler

</details>
