## DW Credit Analysis

### Purpose

This DAG loads to DW our models related to Credit Analysis. 

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load: 

- `credit.dim_credit_analysis`
- `credit.dim_experiment`
- `credit.dim_guarantee_policy`
- `credit.dim_variant`
