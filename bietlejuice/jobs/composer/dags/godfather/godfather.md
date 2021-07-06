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

    - `client_aud`
    - `client`
    - `client_document_aud`
    - `client_document`
    - `client_selfie_document_aud`
    - `client_selfie_document`
    - `message_add_aud`
    - `message_add`
    - `message_aud`
    - `message`
    - `message_modify_aud`
    - `message_modify`
    - `message_price_aud`
    - `message_price`
    - `message_remove_aud`
    - `message_remove`
    - `message_repair_aud`
    - `message_repair`
    - `offer_aud`
    - `offer`
    - `rent_aud`
    - `rent`
    - `rent_flow_aud`
    - `rent_flow`
    - `resident_info_aud`
    - `resident_info`
    - `revinfo`
    - `revived_offer_aud`
    - `revived_offer`
    - `topic_add_aud`
    - `topic_add`
    - `topic_aud`
    - `topic`
    - `topic_modify_aud`
    - `topic_modify`
    - `topic_price_aud`
    - `topic_price`
    - `topic_remove_aud`
    - `topic_remove`
    - `topic_repair_aud`
    - `topic_repair`
    - `user_revision_entity`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>