## Reverse Tracksale
### Purpose
This DAG collects customer data from our DW layer and sends it to the Tracksale API in order to schedule NPS survey dispatches.

Tracksale is an external service that monitors in real time the customer’s experience. We use it to manage NPS and customer reviews.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
All campaigns have been moved to `reverse_tracksale_test` / `reverse_tracksale_access`.
This legacy DAG no longer loads or POSTs campaign tables.

This pipeline also POST data to the Tracksale API (endpoint: `dispatches`) aiming to schedule NPS survey dispatches.

For further information, please read our [Tracksale integration documentation](https://docs.google.com/document/d/15YEa41mdZ2YRUgpKpMNK63sIrHhCSXAYuf2QbW_Df7E) and our [DAG documentation and how to create a dispatch on it](https://www.notion.so/productquintoandar/Reverse-ETL-Tracksale-b6de0bf03f244c8ea4014a7ae916077d).

</details>
