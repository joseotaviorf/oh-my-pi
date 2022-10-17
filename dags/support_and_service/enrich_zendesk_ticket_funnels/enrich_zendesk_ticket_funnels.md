## Enrich Zendesk Ticket Funnels
### Purpose

This is the third layer of the enrichment phase of the Zendesk data preparation. Zendesk is responsible for the tickets of the customer services.

### Execution Interval

This DAG is triggered once per day via Mediator. Please check the dependencies on `dependencies.yaml` file or [here](https://k6ead11b55326f9c9-tp.appspot.com/admin/airflow/graph?dag_id=airflow.dag_dependency_visualization&execution_date=).

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on Enrich layer:

- `ticket_funnel`
- `tickets_funnel_metrics`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
