## Enrich Marketing Costs Sharing Rules

### Purpose

This DAG loads sharing rules defined by Marketing DAs to split costs into regions using processed data.

- Concatenates all rules defined in `$COMPOSER_QUERIES_PATH/enrich_marketing_costs_sharing_rules/online/enrich` for online costs and `$COMPOSER_QUERIES_PATH/enrich_marketing_costs_sharing_rules/offline/enrich` using SQL.

**All queries must have these columns as output:**
- id_date (analogue to sk_date, this column can't be called as sk inside enrich databases)
- city_group
- funnel_side/center_cost (online/offline)
- share

**The rule id is defined by the .sql file name.**

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there are the following output tables in our enrich layer:

- `online`
- `offline`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).