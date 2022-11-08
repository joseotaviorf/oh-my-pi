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

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
