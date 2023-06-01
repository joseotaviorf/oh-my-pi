## Enrich Listing Temp

### Purpose

Creates enriched tables for the context `Listing` of EBDB. 
This is a temporary DAG to create tables similar to house_listing and dim_house_listing to be tested before replacing the original ones.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `dim_house_listing_lbc`
- `fact_house_listing_status_lbc`
- `house_listing_status_lbc`
- `lbc_house_listing`
