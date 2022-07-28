## Enrich Bureaus

### Purpose

Creates enriched tables for the `Bureau` context, transforming data for each of 5A's bureau provider and consolidating them into `all_bureau_analysis` table.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `transunion_bureau_analysis`
- `bigdatacorp_bureau_analysis`
- `neoway_bureau_analysis`
- `serasa_bureau_analysis`
- `all_bureau_analysis`