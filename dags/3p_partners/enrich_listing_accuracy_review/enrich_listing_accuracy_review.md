## Enrich Listing Accuracy Review

### Purpose

This DAG is responsible for creating enriched tables for the feature where the Buyer reviews whether or not the listing visited has the correct information displayed on the platform.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We incrementally load the following tables into the Datalake:

- `listing_accuracy_history`
- `listing_accuracy`

</details>
