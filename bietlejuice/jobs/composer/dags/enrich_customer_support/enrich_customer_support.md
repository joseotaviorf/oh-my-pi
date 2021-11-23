## Enrich Customer Support
### Purpose

Apply all the business rules needed to build an unified ticket vision on DW (Customer Support model). Each row of Call and Chat tables represent one task from a ticket. Each row in the Email table represents one ticket.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once per day via Mediator, please check the dependencies on `dependencies.yaml` file or [here](https://k6ead11b55326f9c9-tp.appspot.com/admin/airflow/graph?dag_id=airflow.dag_dependency_visualization&execution_date=).

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on Enrich layer:

- `chat`
- `csat`
- `call`
- `historical_call`
- `historical_chat`
- `email`

### Disclaimer

In order to run these queries directly from databricks notebook you must replace double brackets for single ones. This occurs because when running on our data pipeline we read and execute these queries using pyspark and to avoid python syntax errors we must escape the brackets characters.
### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>