## Criteo Campaigns
### Purpose

Creates incremental RAW and CLEAN tables with data retrieved from Criteo's API, using our own client integration available in [this API Client Criteo repository](https://github.com/quintoandar/criteo-api-client-python)). Criteo is a retargeting platform - serves ads based on people that have already visited our site - used to show ads to our clients.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there are the following output tables for both our raw and clean layers:

- `criteo_campaigns`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
