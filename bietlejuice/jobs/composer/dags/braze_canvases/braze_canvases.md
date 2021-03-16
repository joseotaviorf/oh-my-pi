## Braze Canvases
### Purpose

Retrieves data from Braze canvases [Details](https://www.braze.com/docs/api/endpoints/export/canvas/get_canvas_details/) and [Analytics](https://www.braze.com/docs/api/endpoints/export/canvas/get_canvas_analytics/) endpoints, according to canvas IDs retrieved from [List](https://www.braze.com/docs/api/endpoints/export/canvas/get_canvases/) endpoint, using [Quinto Andar's Braze API Client](https://github.com/quintoandar/braze-api-client-python).
Braze is a multichannel communication platform. Its Canvas Details data have metadata about a Canvas, such as its name, when it was created, its current status, and more relevant information regarding each canvas, while its Canvas Analytics data contain daily series of various stats for a canvas over time.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG executes multiple requests using Spark parallel processing to get all the Braze canvas records according to each endpoint and app group - looped in the Spark job using the `ENDPOINTS` and `APP_GROUPS` variables, respectively. It generates the respective output tables.

This pipeline produces, via full load:

1. In datalake raw and clean:
- `canvases_analytics_owners`
- `canvases_analytics_tenants`
- `canvases_details_owners`
- `canvases_details_tenants`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
