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

- `sale_listing_traffic`
- `sale_listing_published`
- `sale_listing_visit_scheduled`
- `sale_listing_visit_confirmed`
- `sale_listing_offer_sent`
- `sale_listing_offer_accepted`
- `sale_listing_signed_contract`

</details>
