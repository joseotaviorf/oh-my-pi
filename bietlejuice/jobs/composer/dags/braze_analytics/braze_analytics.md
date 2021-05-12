## Braze Analytics
### Purpose

Retrieves Analytics data from [Campaigns](https://www.braze.com/docs/api/endpoints/export/campaigns/get_campaign_analytics/) and [Canvases](https://www.braze.com/docs/api/endpoints/export/canvas/get_canvas_analytics/) identifier endpoints, according to each identifier ID retrieved from [Campaigns List](https://www.braze.com/docs/api/endpoints/export/campaigns/get_campaigns/) and [Canvases List](https://www.braze.com/docs/api/endpoints/export/canvas/get_canvases/) endpoints respectively, using [Quinto Andar's Braze API Client](https://github.com/quintoandar/braze-api-client-python).
Braze is a multichannel communication platform. Its Canvas Analytics data contain daily series of various stats for a canvas over time, while its Campaign Analytics data contain daily series of various stats for a campaign over time.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG executes multiple requests using Spark parallel processing to get the Braze analytics records according to each identifier and app group, with a Spark Job for each combination of values in the `IDENTIFIERS` and `APP_GROUPS` variables in the DAG script.

This pipeline produces, via incremental load:

- In datalake raw and clean:
    - `campaign_analytics_owners`
    - `campaign_analytics_tenants`
    - `canvas_analytics_owners`
    - `canvas_analytics_tenants`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
