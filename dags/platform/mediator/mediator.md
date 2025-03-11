## Mediator

### Purpose

This DAG triggers the DAGs that have cross-DAG dependencies.
Each dependent DAG declared in the [dependencies.yaml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/dags/dependencies.yaml) will have a trigger task in this DAG.
The task `check-dependencies` checks for dependencies completion and skips the dependents DAGs' triggers that are not ok
to be triggered.
To force the Mediator to skip a DAG temporarily, use the variable [MEDIATOR_SKIP_LIST](/d03z8k7v/variable/list/?_flt_0_key=MEDIATOR_SKIP_LIST#).

### Execution Interval

Runs at every 10 minutes, starting at minute 0 of each hour. More information about run time [here]({chart_url}{dag_id}).

*Dies (timeout) after 9 minutes.*

### Additional Information

- [Mediator documentation page](https://www.notion.so/productquintoandar/Mediator-8c1bf75670bf4dc2999d17b12a3b2ec1)
- [DAG Mediator Plugin](https://github.com/quintoandar/airflow-plugins/blob/master/quintoandar_airflow_plugins/dag_mediator_plugin.md)
