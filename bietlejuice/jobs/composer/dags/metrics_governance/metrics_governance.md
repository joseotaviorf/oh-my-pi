## Metrics Governance


### Purpose
Gets QuintoAndar Metrics that were registered through the Metrics Governance project.

The metrics are stored in the data-documentation S3 bucket.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
We incrementally load the following tables into the datalake Raw and Clean:

- Raw
  - `datalake_metrics_governance_raw.metrics_registration`

- Clean
  - `datalake_metrics_governance_clean.metrics_registration`

</details>
