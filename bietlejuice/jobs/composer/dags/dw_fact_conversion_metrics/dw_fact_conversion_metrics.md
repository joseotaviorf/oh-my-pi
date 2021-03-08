## DW Fact Conversion Metrics
### Purpose

This dag loads the models that we use to support our client analysis. There is one for both tenants and owners; The point is to provide some metrics about our clients and how it relates to their interactions on our platform.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there are the following output tables in our DW layer:

- `fact_owner_conversion_metrics`
- `fact_tenant_conversion_metrics`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
