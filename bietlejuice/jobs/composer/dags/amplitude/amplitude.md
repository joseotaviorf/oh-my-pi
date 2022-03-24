### Purpose

Amplitude is a product analytics tool that we use at Quinto Andar to help track visitor behaviour. We use the events in conjunction with our major Facts and Dims; focused mostly on enriching them (such as enriching user information onto leads.) More information about how the tool works can be found on [their site](https://amplitude.com/) For more information on how the DAG itself works please refer to [this document](https://docs.google.com/document/d/1an1aankHwGmgumcebXeaA3U1YUIcEXXzpZbTSzmWCe8/edit).
### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table for both our raw, staging (clean) and clean layers:

- `events`
- `170698_user_merge`
  
### Note about data flow

The DAG extracts events data direct from Amplitude API and creates multiple tables by event type. The raw data from user merge isn't ingested to datalake by the DAG, it just creates a clean table. In fact, there is a [automation](https://analytics.amplitude.com/quintoandar/connections/project/170698/destinations) created at Amplitude app to drop data in S3 bucket.
### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
