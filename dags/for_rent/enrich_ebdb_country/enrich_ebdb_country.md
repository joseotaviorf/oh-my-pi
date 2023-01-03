## Enrich EBDB Country

### Purpose

Creates enriched tables in order to relate different entities to the country of origin, where the source is the EBDB. 
Every table is partitioned by the `country_code`, some may have extra partitions.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

- `house`, partitioned by `country_code` and `business_context`
- `user`, partitioned by `country_code`

