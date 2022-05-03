## Stilingue
### Purpose

Stilingue [client API](https://github.com/quintoandar/stilingue-api-client-python) is a social listening and responding platform. We use the data from this service to serve the public and to generate sentiment analysis and classification.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table for both our raw, staging (clean) and clean layers:

- `smartcare_facebook_conversations`
- `smartcare_instagram_conversations`
- `smartcare_twitter_conversations`
- `smartcare_youtube_conversations`
- `smartcare_linkedin_conversations`
- `social_media_pages`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).