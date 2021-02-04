## Mediator

### Purpose

This DAG triggers the DAGs that have cross-DAG dependencies.
Each dependent DAG declared in the [dependencies.yaml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/dependencies.yaml) will have a trigger task in this DAG.
The task `check-dependencies` checks for dependencies completion and skips the dependents DAGs' triggers that are not ok
to be triggered.

To force the Mediator to skip a DAG temporarily, use the variable [MEDIATOR_SKIP_LIST](/admin/variable/?flt1_0=MEDIATOR_SKIP_LIST).

### Execution Interval

Runs at minutes 0 and 30, each hour. More information about run time [here]({chart_url}{dag_id})

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

### Additional Information

- [Mediator documentation page](https://www.notion.so/productquintoandar/Mediator-8c1bf75670bf4dc2999d17b12a3b2ec1)
- [DAG Mediator Plugin](https://github.com/quintoandar/airflow-plugins/blob/master/quintoandar_airflow_plugins/dag_mediator_plugin.md)
