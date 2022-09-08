## DW Invoice Entries Snapshot

​

### Purpose

​
This DAG creates a snapshot of the invoice entry tables.
​

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered when execution_date is the first business day, monthly, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

​
This pipeline produces the following output tables, in DW schema `payment_snapshot`, via full load:​​

- `dim_invoice_snapshot`
- `dim_invoice_entry_snapshot`
- `fact_invoice_entries_snapshot`
​
</details>
