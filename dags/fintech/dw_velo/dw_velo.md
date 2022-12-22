## DW Velo


### Purpose

​
This DAG creates the star schema model for Velo context.
​

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

​
This pipeline produces the following output model, in DW schema `velo`, via full load:​​

- `bridge_velo_propose_person`
- `dim_velo_broker`
- `dim_velo_house`
- `dim_velo_junk`
- `dim_velo_propose_company`
- `dim_velo_propose_person`
- `dim_velo_propose_values`
- `dim_velo_transaction_category`
- `dim_velo_transaction`
- `dim_velo_user`
- `fact_velo_propose`
- `fact_velo_transaction_entries`
​
</details>
