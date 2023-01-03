## Enrich Proposal

### Purpose

Creates enriched tables for the context `Proposal` enriching from EBDB, Sorting Hat and Rental Guarantee.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table, partitioned by `country_code`:

- `proposal`
