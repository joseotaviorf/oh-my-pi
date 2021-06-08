## Repairs

### Purpose

This DAG handles the ingestion of the raw and clean data for our Repairs Service, which is a Service that was created to make repairs experience faster and easier for Tenants and Landlords. Check [its own repository](https://github.com/quintoandar/repairs) for more informations.

### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw:
    - All tables mapped in the clean layer which are available in the source's database.

2. In datalake clean:
    - `instant_approval_preference_aud`
    - `instant_approval_preference`
    - `repair_evidence_aud`
    - `repair_evidence`
    - `repair_expense_aud`
    - `repair_expense`
    - `repair_expense_group_aud`
    - `repair_expense_group`
    - `repair_request_aud`
    - `repair_request`
    - `repair_request_item_aud`
    - `repair_request_item`
    - `rev_info`
    
### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
