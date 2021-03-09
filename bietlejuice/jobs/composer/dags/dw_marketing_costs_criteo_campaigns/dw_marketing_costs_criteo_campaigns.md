## DW Marketing Costs Criteo Campaigns
### Purpose

Criteo is a retargeting platform (serves ads based on people that have already visited our site.) We use them to send campaigns to our clients. This DAG creates the fact and dim based off of the data that they provide to us via API (Accessible via our [Criteo Repository](https://github.com/quintoandar/criteo-api-client-python)).

### Dag Dependencies
`enrich_marketing_costs_criteo_campaigns`


### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there are the following output tables for both our staging and dw layers:

- `fact_criteo_daily_cost_attributions`
- `dim_criteo_campaign`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
