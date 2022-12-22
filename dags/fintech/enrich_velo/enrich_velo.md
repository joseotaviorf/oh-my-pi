## Enrich Velo

### Purpose

Creates enriched tables for Velo Propose and Transactions context.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `broker`
- `house`
- `propose`
- `propose_company`
- `propose_person`
- `propose_values`
- `user`
- `transaction_entries`
- `transaction_category`
- `junk`
