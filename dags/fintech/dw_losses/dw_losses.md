## DW Losses

### Purpose

This DAG loads to DW the fact table for the closing information regarding the losses modelation: fact_closing. 

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load :

- `dw_losses.fact_closing`
