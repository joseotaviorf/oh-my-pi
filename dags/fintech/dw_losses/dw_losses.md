## DW Losses

### Purpose

This DAG loads to the DW the fact tables for the losses modelation: fact_closing, fact_delay and fact_provision.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load :

- `dw_losses.fact_closing`
- `dw_losses.fact_delay`
- `dw_losses.fact_provision`
- `dw_losses.dim_provision_factor`
- `dw_losses.dim_bill_items`
