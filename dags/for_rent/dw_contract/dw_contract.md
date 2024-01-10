## DW Contract

### Purpose

This DAG loads to DW our models related to the contracts context.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load:

- `dw_rent.dim_contract`
- `dw_rent.dim_contract_person`
- `dw_rent.fact_contract_people`

</details>
