## DW Invoice Entries

​

### Purpose

​
This DAG creates the fact model for invoice entries.
​

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

​
This pipeline produces the following output model, in DW schema `payment`, via full load:​​

- `dim_invoice`
- `dim_invoice_entry`
- `fact_invoice_entries`
​
</details>
