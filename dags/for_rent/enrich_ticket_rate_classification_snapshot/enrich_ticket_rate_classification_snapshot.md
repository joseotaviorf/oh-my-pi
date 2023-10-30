## Enrich Ticket Rate Classification Snapshot


### Purpose
​
This DAG creates a snapshot of the table ticket_rate_classification in order to keep track of the changes that could undesirebly change ticket_rate metrics.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered every time the static gsheet ticket_rate_classification is loaded, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables, in Enrich layer, full load:​​

- `datalake_ticket_rate_classification_snapshot.ticket_rate_classification`

​
</details>
