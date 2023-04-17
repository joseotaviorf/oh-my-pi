## Enrich B2B

### Purpose

Creates enriched table for the context `B2B`.
This schema has tables that extracts data about houses/house listings to check if the listing is from a b2b partner.

### Execution Interval
This DAG is triggered daily, via Mediator. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table, via full load:
- `house_listing`
