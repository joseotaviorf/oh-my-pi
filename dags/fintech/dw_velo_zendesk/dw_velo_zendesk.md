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

- `dim_velo_ticket_user`
- `dim_velo_ticket_details`
- `fact_velo_ticket_metrics`
​
</details>
