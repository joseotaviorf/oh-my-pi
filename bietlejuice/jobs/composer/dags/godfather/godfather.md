## Godfather

### Purpose

This DAG extracts data from [Godfather](https://github.com/quintoandar/godfather), a negotiation platform used by both owners and prospective tenants.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:

1. Data lake raw:

    - All tables in database.

2. Data lake clean:

    On `audit` context:

    - `client_aud`
    - `client_document_aud`
    - `client_selfie_document_aud`
    - `message_add_aud`
    - `message_aud`
    - `message_modify_aud`
    - `message_price_aud`
    - `message_remove_aud`
    - `message_repair_aud`
    - `offer_aud`
    - `rent_aud`
    - `rent_flow_aud`
    - `resident_info_aud`
    - `revinfo`
    - `revived_offer_aud`
    - `topic_add_aud`
    - `topic_aud`
    - `topic_modify_aud`
    - `topic_price_aud`
    - `topic_remove_aud`
    - `topic_repair_aud`
    - `user_revision_entity`

    On `business` context:
    
    - `client`
    - `client_document`
    - `client_document_analysis`
    - `client_selfie_document`
    - `client_selfie_document_analysis`
    - `cloned_firestore_entity`
    - `contract`
    - `documentation`
    - `house`
    - `message`
    - `message_add`
    - `message_modify`
    - `message_price`
    - `message_remove`
    - `message_repair`
    - `offer`
    - `rent`
    - `rent_flow`
    - `resident_info`
    - `revived_offer`
    - `topic`
    - `topic_add`
    - `topic_modify`
    - `topic_price`
    - `topic_remove`
    - `topic_repair`
    - `user_info`
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>