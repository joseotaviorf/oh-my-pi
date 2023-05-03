## DW Business Unit Region

### Purpose

This DAG loads business unit region table to DW.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load:

- `sale.fact_business_unit_region`

</details>
