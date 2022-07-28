## Enrich Zendesk Custom Fields
### Purpose

This is the first layer of the enrichment phase of the Zendesk data preparation. The `custom_fields` column is a key-value data structure, the keys are IDs and the value can be many different things as _client type_, IDs of other systems and etc.. Zendesk is responsible for the tickets of the customer services.

### Execution Interval

This DAG is triggered once per day via Mediator. Please check the dependencies on `dependencies.yaml` file or [here](https://k6ead11b55326f9c9-tp.appspot.com/admin/airflow/graph?dag_id=airflow.dag_dependency_visualization&execution_date=).

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on Enrich layer:

- `custom_fields`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
