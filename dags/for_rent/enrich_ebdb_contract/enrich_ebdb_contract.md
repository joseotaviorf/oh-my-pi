## Enrich EBDB Contract

### Purpose

Creates enriched tables for the context `Contract` of ebdb.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load, partitioned by `country_code`:

- `contract`
- `contract_b2b`
- `contract_house`
- `contract_person`
- `ongoing_contracts`

