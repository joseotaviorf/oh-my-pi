## Braze Campaigns
### Purpose

Retrieves data from Braze campaigns [Details](https://www.braze.com/docs/api/endpoints/export/campaigns/get_campaign_details/) and [Analytics](https://www.braze.com/docs/api/endpoints/export/campaigns/get_campaign_analytics/) endpoints, according to campaign IDs retrieved from [List](https://www.braze.com/docs/api/endpoints/export/campaigns/get_campaigns/) endpoint, using [Quinto Andar's Braze API Client](https://github.com/quintoandar/braze-api-client-python).
Braze is a multichannel communication platform. Its Campaign Details data have relevant information regarding each campaign, while its Campaign Analytics data contain daily series of various stats for a campaign over time.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG executes multiple requests using Spark parallel processing to get all the Braze campaign records according to each endpoint and app group - looped in the Spark job using the `ENDPOINTS` and `APP_GROUPS` variables, respectively. It generates the respective output tables.

This pipeline produces, via full load:

- In datalake raw and clean:
    - `campaigns_analytics_owners`
    - `campaigns_analytics_tenants`
    - `campaigns_details_owners`
    - `campaigns_details_tenants`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
