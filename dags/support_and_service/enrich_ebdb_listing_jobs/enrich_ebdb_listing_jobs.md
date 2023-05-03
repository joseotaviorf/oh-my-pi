## Enrich EBDB Listing Jobs

### Purpose

Creates enriched tables for the context `Listing Jobs` of ebdb, like
inspection and photo_job.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, partitioned by `country_code`:

- `inspection`
- `photo_job`
