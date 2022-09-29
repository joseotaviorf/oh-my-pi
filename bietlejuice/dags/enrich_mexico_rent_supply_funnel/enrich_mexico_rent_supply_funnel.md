## Enrich Mexico Rent Supply Funnel

### Purpose

This DAG creates the enriched tables related to Benvi Mexico's Rent Supply Funnel.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Creates the enriched tables via full load, partitioned by `country_code`: 

- `cohort_funnel`, soon to be migrated to the metric layer.
- `coincident_funnel`, soon to be migrated to the metric layer.
- `listing_flow`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact its owner.