## DW Retsuko

### Purpose

This DAG creates the Retsuko model, which provides information about payments.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This dag is triggered once per day via Mediator. More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output tables:

- `dw_rental_payments.dim_bill_item`
- `dw_rental_payments.fact_invoice_status_changes`

</details>
