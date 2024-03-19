## Reverse Listings Report Access

### Purpose

This DAG collects data saved in the schema "reverse_listings_report" by the DAG reverse_listings_report_load, and sends
them via SNS to a service called "Member's Area". There, they will be displayed as an analytical report for Rede Members.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline exports the following tables from the reverse_listings_report schema to an SNS topic:

- `pricing_report_engagement`
- `pricing_report_listing_price_history`

</details>
