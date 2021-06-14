## Survicate
### Purpose

Retrieves surveys from [Survicate](https://developers.survicate.com/data-export/#get-the-list-of-surveys). Today we are using this tool to create surveys to collect user CSAT for email tickets

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG runs Spark jobs that execute requests using our [survicate python client](https://github.com/quintoandar/survicate-api-client-python). First we make a single request to survey_list endpoint to get a list with all survey_ids and after we use this list to fetch incrementally all new responses from these surveys

This pipeline produces, via incremental load (layers raw and clean):
    - `surveys`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
