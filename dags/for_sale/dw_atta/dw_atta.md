## DW ATTA

### Purpose
This DAG creates the ATTA star schema model.
​

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

​
This pipeline produces the following output model, in DW schema `atta`, via full load:​​

- `fact_pre_analysis_proposal_flow`
- `dim_proposal_atta`
- `dim_consultant_atta`
- `dim_client_atta`
- `dim_franchise_atta`
- `dim_partner_atta`
- `dim_buyer_atta`
​
</details>
