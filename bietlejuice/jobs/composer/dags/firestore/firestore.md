## Firestore

### Purpose
This DAG ingests audit data for ForSale from Cloud Firestore collections. This integration is also using our Pub/Sub integration.

Besides of being audit data, there is the possibility of duplicate lines due to the "at least once" nature.

### Execution Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces, via incremental load:

1. In datalake raw and clean:
    - `monday`
    - `rent_offer`
    - `sale_offer`

### Responsible Data Teams
For any questions or concerns about this DAG, please contact the Data Engineering Team or the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
