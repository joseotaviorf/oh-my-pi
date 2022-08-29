## DW Tickets
### Purpose
​
This DAG loads the DW tables of our Tickets data. This data is related to the external system named Zendesk, which is responsible for the tickets of the customer services.
​
​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>​

### Execution Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:
​
- `dim_repair_tickets`
- `dim_ticket`
- `dim_zendesk_user`
- `fact_repair_tickets`
- `fact_ticket_contact_types`
- `fact_ticket_tags`
- `fact_tickets`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact its owner.

</details>