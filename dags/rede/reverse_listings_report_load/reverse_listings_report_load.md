## Reverse Listings Report Load

### Purpose

This DAG collects several events from listings (currently, only focused on Rede Sale Listings). These tables
will be used in the DAG reverse_listings_report_access to be sent via SNS to a service called "Member's Area",
where they will be displayed as an analytical report for Rede Members.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We incrementally load the following tables into the Datalake:

- `sale_listing_traffic`
- `sale_lead_not_converted`
- `sale_listing_published`
- `sale_listing_visit_scheduled`
- `sale_listing_visit_confirmed`
- `sale_listing_offer_sent`
- `sale_listing_offer_accepted`
- `sale_listing_signed_contract`

</details>
