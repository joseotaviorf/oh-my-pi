## Enrich Losses

### Purpose

Creates enriched tables for the `Losses` context, which aims to analyze NPV for Rental Contracts, initially.
#### This Dag has a table from the DW as a dependency

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `closing`
- `delay`
- `historical_closing`
- `provision`
- `provision_factor`
- `bill_items`
