## Enrich Analyst Ranking
### Purpose

Enrich layer to apply all the business rules required to build the analyst ranking.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once per day via Mediator, please check the dependencies on `dependencies.yaml` file or [here](https://k6ead11b55326f9c9-tp.appspot.com/admin/airflow/graph?dag_id=airflow.dag_dependency_visualization&execution_date=).

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on Enrich layer (incremental load):

- `analyst_metrics`
- `ranking`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering team responsible listed in the DAG owners.

</details>