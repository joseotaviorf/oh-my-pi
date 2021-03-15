## Zendesk Tickets
### Purpose

Load data of the Zendesk to the Clean layer, the Raw layer is loaded by Stitch. Zendesk is responsible for the tickets of the customer services.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We perform a incremental load of the following table into the datalake Clean.

- `group_memberships`
- `groups`
- `ticket_fields`
- `ticket_metrics`
- `tickets`
- `users`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
