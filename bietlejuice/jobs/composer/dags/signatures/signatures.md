## Signatures

### Purpose

Extraction of Signatures tables into data lake. Signatures is the service responsible for documents signature operations.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

1. In datalake raw:
    - All tables available in source's database, except for Operationals (flyway_schema_history) and some trash (agreement_document_bkp, change_owner_control).

2. In datalake clean:
    - `agreement_document`
    - `agreement_document_aud`
    - `recipient`
    - `recipient_aud`
    - `rev_info`
    - `signature`
    - `signature_aud`
    - `signature_collector`
    - `signature_collector_aud`
   
### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
