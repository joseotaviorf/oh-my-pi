## Enrich Mexico Rent Demand

### Purpose

This DAG creates the enriched tables related to Benvi Mexico's Rent Demand Funnel.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Creates the enriched tables via full load, partitioned by `country_code`: 

- `monthly_demand_funnel`
- `weekly_demand_funnel`
