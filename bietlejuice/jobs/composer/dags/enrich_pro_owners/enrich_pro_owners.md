## Enrich Pro Owners

### Purpose

Creates enriched tables for the context `Pro_owners` from ebdb. This schema has tables that
extract metrics about owners and houses like quantity of house, owner classification, owner account manager 
and their changes in time. So, the grain in these tables is a owner, ts_change and a metric that was observed.
Basically, a SCD type 2.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `owner_houses_quantity_history`
- `pro_owner_history`

