## Braze Events
### Purpose

Retrieves data from events streamed by [Braze's Currents tool](https://www.braze.com/docs/user_guide/data_and_analytics/braze_currents/).
Braze is a multichannel communication platform, and its tool Currents is responsible for streaming event data into our infrastructure.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG gets all the Braze integrations declared in the DAG file constant `APP_GROUPS` and generates a respective output table.
For more information about how to setup these integrations, please refer to [this Notion page](https://www.notion.so/productquintoandar/Currents-Events-5e474fe0c1684df98e1423cdb8afad3f).

Currently, the output tables are the following:

- `events_owners`
- `events_tenants`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
