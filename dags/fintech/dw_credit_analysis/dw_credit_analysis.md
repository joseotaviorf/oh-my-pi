## DW Credit Analysis

### Purpose

This DAG loads to DW our models related to Credit Analysis. 

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load: 

- `dw_credit.dim_credit_analysis`
- `dw_credit.dim_experiment`
- `dw_credit.dim_guarantee_policy`
- `dw_credit.dim_variant`
- `dw_credit.fact_proposal_credit_flows`
- `dw_credit.fact_fintechops_tasks`
- `dw_credit.fact_credit_engine_analysis_request`