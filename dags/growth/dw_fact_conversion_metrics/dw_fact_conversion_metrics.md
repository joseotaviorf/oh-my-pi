## DW Fact Conversion Metrics
### Purpose

This DAG loads the models that we use to support our client analysis. There is one for both tenants and owners; The point is to provide some metrics about our clients and how they relate to their interactions on our platform.

<details>
    <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output tables in DW layer, created in `quintoandar` schema:

- `quintoandar.fact_owner_conversion_metrics`
- `quintoandar.fact_tenant_conversion_metrics`

</details>
