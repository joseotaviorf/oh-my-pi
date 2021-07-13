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
This pipeline produces the following output tables, in datalake raw and clean, via full load:
    - `client`
    - `client_aud`
    - `client_document`
    - `client_document_aud`
    - `client_selfie_document`
    - `client_selfie_document_aud`
    - `message`
    - `message_aud`
    - `message_modify`
    - `message_modify_aud`
    - `message_price`
    - `message_price_aud`
    - `message_remove`
    - `message_remove_aud`
    - `message_repair`
    - `message_repair_aud`
    - `offer`
    - `offer_aud`
    - `rent`
    - `rent_aud`
    - `rent_flow`
    - `rent_flow_aud`
    - `resident_info`
    - `resident_info_aud`
    - `rev_info`
    - `revived_offer`
    - `revived_offer_aud`
    - `topic`
    - `topic_aud`
    - `topic_add`
    - `topic_add_aud`
    - `topic_modify`
    - `topic_modify_aud`
    - `topic_price`
    - `topic_price_aud`
    - `topic_remove`
    - `topic_remove_aud`
    - `topic_repair`
    - `topic_repair_aud`
    - `user_revision_entity`

### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>