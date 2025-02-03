## DW Fintech Snapshot


### Purpose
​
This DAG creates a snapshot of table dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered when execution_date is the seconds business day, monthly, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables, in DW layer, incrementally:​​

- `dw_payment_snapshot.fact_overdue_portfolio_timeline_snapshot`
​
</details>
