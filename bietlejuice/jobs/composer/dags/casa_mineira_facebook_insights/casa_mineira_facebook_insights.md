## Casa Mineira Facebook Insights

### Purpose

Casa Mineira Facebook Insights DAG retrieves Casa Mineira's marketing campaign insights data from Facebook platform. It uses data extracted from [Facebook Marketing API Insights endpoint](https://developers.facebook.com/docs/marketing-api/insights/) using [Quinto Andar's Facebook API Client](https://github.com/quintoandar/facebook-api-client-python), with the access token from [Facebook Casa Mineira App](https://developers.facebook.com/apps/873195336192698/marketing-api/tools/?business_id=821145501325675).
Social accounts have a separated task as they require a special breakdown/field format.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via incremental load:

- In datalake raw and clean:
    - `facebook_insights`
    - `facebook_social_insights`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
