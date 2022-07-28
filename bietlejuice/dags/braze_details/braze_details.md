## Braze Details
### Purpose

Retrieves Details data from [Campaigns](https://www.braze.com/docs/api/endpoints/export/campaigns/get_campaign_details/) and [Canvases](https://www.braze.com/docs/api/endpoints/export/canvas/get_canvas_details/) identifier endpoints, according to each identifier ID retrieved from [Campaigns List](https://www.braze.com/docs/api/endpoints/export/campaigns/get_campaigns/) and [Canvases List](https://www.braze.com/docs/api/endpoints/export/canvas/get_canvases/) endpoints respectively, using [Quinto Andar's Braze API Client](https://github.com/quintoandar/braze-api-client-python).
Braze is a multichannel communication platform. Its Canvas Details data have metadata about a Canvas, such as its name, when it was created, its current status, and more relevant information regarding each canvas, while its Campaign Details data have relevant information regarding each campaign.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG executes multiple requests using Spark parallel processing to get the Braze details records according to each identifier and app group, with a Spark Job for each combination of values in the `IDENTIFIERS` and `APP_GROUPS` variables in the DAG script.

This pipeline produces, via full load:

- In datalake raw and clean:
    - `campaign_details_owners`
    - `campaign_details_tenants`
    - `canvas_details_owners`
    - `canvas_details_tenants`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>