## Enrich Unified Listing Flow

### Purpose

Replica of enrich_listing_flow DAG. This DAG it's been used for tests about unifying rent and sale tables into one.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

- `discards_reason_by_context`
- `listing_flow`
- `listing_flows_with_reprocessed_leads`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
