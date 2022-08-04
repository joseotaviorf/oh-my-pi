## Enrich Contract

### Purpose

Creates enriched table for the context `Contract` of various sources as EBDB and Retsuko. This enriched data will be used for `dim_contract` table.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `contract`

