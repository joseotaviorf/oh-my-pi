## DW Fintech Snapshot


### Purpose
​
This DAG creates a snapshot of several tables in order to provide "time travel" for Finance Team.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered when execution_date is the first business day, monthly, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables, in DW layer, incrementally:​​

- `dw_payment_snapshot.dim_invoice_snapshot`
- `dw_payment_snapshot.dim_invoice_entry_snapshot`
- `dw_payment_snapshot.fact_invoice_entries_snapshot`
- `dw_public_snapshot.dim_contract`
​
</details>
