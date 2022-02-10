## DW Tenant Documentation
​
### Purpose
​
Full load of the context Tenant Documentation model into DW with data from ebdb.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces in DW, schema quintoandar, via full load:
    - `dim_credit_documentation`
    - `fact_tenant_proponent_documentation`
​