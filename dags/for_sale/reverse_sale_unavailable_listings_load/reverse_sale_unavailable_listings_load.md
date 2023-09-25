## Reverse Listings Sale Unavailable Listings Load

### Purpose

This DAG consolidates data from various sources on the demand for listings and their behavior and creates tables that generate a list of possibly unavailable listings.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We incrementally load the following tables into the Datalake:

- `suspected_unavailable_listings`

</details>
