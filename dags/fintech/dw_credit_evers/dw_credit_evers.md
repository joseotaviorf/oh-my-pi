## DW Credit Evers

### Purpose

This DAG loads to DW our models related to Credit Evers.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load:

- `dw_credit_evers.fact_credit_evers_original_due_date`

