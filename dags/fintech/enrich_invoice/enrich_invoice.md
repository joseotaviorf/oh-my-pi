## Enrich Invoice

### Purpose

This DAG creates the full table for credit invoice enrichment, with information about payments.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table:

1. In data lake enrich:

- `credit_invoice`
- `invoice_all`
- `invoice_entries`
- `invoice_revenues`
</details>
