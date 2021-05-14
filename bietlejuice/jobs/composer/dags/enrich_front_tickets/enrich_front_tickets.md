## Enrich Front Tickets
### Purpose

Apply all the business rules needed to build an unified ticket vision on DW (Front Tickets model). Each row of Call and Chat tables represent one task from a ticket. Each row in the Email table represents one ticket.

### Execution Interval

This DAG is triggered once per day via Mediator, please check the dependencies on `dependencies.yaml` file or [here](https://k6ead11b55326f9c9-tp.appspot.com/admin/airflow/graph?dag_id=airflow.dag_dependency_visualization&execution_date=).

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on Enrich layer:

- `chat`
- `chat_historical`
- `call`
- `email`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
