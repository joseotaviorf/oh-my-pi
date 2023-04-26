## Velo Zendesk Tickets
### Purpose

Load data of the Velo's Zendesk to the Clean layer, the Raw layer is loaded by Stitch. Zendesk is responsible for the tickets of the customer services.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We perform a full load of the following table into the datalake Clean.

- `group_memberships`
- `groups`
- `ticket_fields`
- `ticket_metrics`
- `tickets`
- `users`

</details>
