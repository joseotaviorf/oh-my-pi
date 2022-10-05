## DW Agent Contract

### Purpose

​This DAG loads into `dw_agent` tables related to agents and their work contracts.

​<details>

  <summary><strong> > DAG details (click to expand)</strong></summary>​
​
### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables, fully:

- `dim_work_contract`
- `fact_agent_contract`

</details>
