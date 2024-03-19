## Reverse Listings Report Load

### Purpose

This DAG collects several events from properties. These tables
will be used in the DAG reverse_atlas_pricing_report_access to be sent via SNS,
where they will be displayed as an analytical report for Atlas.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We incrementally load the following tables into the Datalake:

- `pricing_report_engagement`
- `pricing_report_listing_price_history`

</details>
