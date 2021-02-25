## Firestore

### Purpose
This DAG ingest data for ForSale from Cloud Firestore collections. This integration is also using our Pub/Sub integration.

### Execution Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces, via incremental load:

1. In datalake raw and clean:
    - `monday`
    - `rent_offer`
    - `sale_offer`

### Responsible Data Engineering Team
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).