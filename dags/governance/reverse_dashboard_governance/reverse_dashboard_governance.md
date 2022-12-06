## Reverse Dashboard Governance

### Purpose

This DAG collects data from datalake_dashboard_governance tables and send them to metadata propagator.
Metadata propagator is a service that is used to send data to our data catalog (DataHub)

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline only sends requests to metadata propagator and does not generate other outputs.

</details>
