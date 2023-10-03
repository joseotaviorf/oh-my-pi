## Enrich Losses Daily

### Purpose

Creates enriched tables for the `Losses` context, this is the dag responsible to generate the daily snapshot.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:


- `closing`
- `delay`
- `provision`
- `pdd`