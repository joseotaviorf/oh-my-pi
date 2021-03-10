## Enrich EBDB User Revision Entity

### Purpose

Creates enriched tables for the context `User Revision Entity` of ebdb adding
milliseconds to ts_revision column as a default timestamp format.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

1. In data lake enrich:
    - `user_revision_entity`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
