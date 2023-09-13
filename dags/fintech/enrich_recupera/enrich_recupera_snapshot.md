## Enrich Recupera


### Purpose
​
This DAG creates a snapshot of table daily_debts in order to provide "time travel" for Collection Recovery analysis.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily after DAG bietlejuice.recupera, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables, in Enrich layer, incrementally:​​

- `datalake_recupera.snapshot_daily_debts`
​
</details>
