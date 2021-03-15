## DW Tickets
### Purpose
​
This DAG loads the DW tables of our Tickets data. This data is related to the external system named Zendesk, which is responsible for the tickets of the customer services.
​
### Execution​ Interval
This DAG is triggered once per day via Mediator. Please check the dependencies on the `dependencies.yaml` file or [here](https://k6ead11b55326f9c9-tp.appspot.com/admin/airflow/graph?dag_id=airflow.dag_dependency_visualization&execution_date=).

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:
​
- `dim_ticket`
- `dim_zendesk_user`
- `fact_ticket_contact_types`
- `fact_ticket_tags`
- `fact_tickets`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
