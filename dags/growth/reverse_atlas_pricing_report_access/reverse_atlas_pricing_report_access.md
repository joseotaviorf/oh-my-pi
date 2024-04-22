## Reverse Listings Report Access

### Purpose

This DAG retrieves data stored in the `datalake_atlas_pricing_report` schema,
which was previously processed by the DAG enrich_atlas_pricing_report, and transmits
it through SNS. This dataset serves as the foundation for generating pricing reports
to QuintoAndar Seekers.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline exports the following tables from the `datalake_atlas_pricing_report` schema to an SNS topic:

- `new_pricing_report_region`
- `new_pricing_report_engagement`
- `new_pricing_report_listing_price_history`
- `new_pricing_report_new_rent_price_published`

</details>
