## Enrich Rental Listing Metrics

### Purpose

Creates enriched tables that has rental listings metrics like the amount of publicated listings in a week or cohort analysis. Usually the date values drives the tables of this DAG. 

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

- `cohort_listings_20w`
- `cohort_listings_weekly`
- `coincident_listings_weekly`
​

​</details>