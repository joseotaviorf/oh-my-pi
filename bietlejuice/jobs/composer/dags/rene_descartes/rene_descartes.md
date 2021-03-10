## Rene Descartes

### Purpose

This DAG handles the ingestion of our raw and clean data for our Rene Descartes Microservice, which is a Microservice for Owner Lead discard rules. For more information about the Database please refer to [the repository](https://github.com/quintoandar/rene-descartes).


### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw:
    - All tables which are available in the source's database.

2. In datalake clean:
    - `acquisition_misc_data`
    - `address_aud`
    - `address`
    - `house_lead_aud`
    - `house_lead`
    - `lead_rejection_aud`
    - `lead_rejection`
    - `owner_aud`
    - `owner`
    - `phone`
    - `rejection_history_collector_aud`
    - `rejection_history_collector`
    - `rejection_history_event_aud`
    - `rejection_history_event`
### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
