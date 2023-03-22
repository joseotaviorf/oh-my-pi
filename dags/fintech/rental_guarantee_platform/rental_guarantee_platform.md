## Rental Guarantee Platform

### Purpose

This DAG imports the tables from **Rental Guarantee Platform**, a For Brokers service that provides insurance against loss of rent for real estate agencies.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake_rental_guarantee_platform_raw:

Via **incremental load**:

    - `address_aud`
    - `company`
    - `company_aud`
    - `company_draft`
    - `company_draft_aud`
    - `company_user_account`
    - `company_user_account_aud`
    - `contract`
    - `contract_aud`
    - `contract_item`
    - `contract_item_aud`
    - `contract_payment`
    - `contract_payment_aud`
    - `contract_payment_hook_history`
    - `contract_payment_hook_history_aud`
    - `contract_person`
    - `contract_person_aud`
    - `contract_status_history`
    - `contract_status_history_aud`
    - `credit_analysis`
    - `credit_analysis_aud`
    - `income_document`
    - `income_document_aud`
    - `person`
    - `person_aud`
    - `profile_account`
    - `profile_account_aud`
    - `property`
    - `property_aud`
    - `revinfo`
    - `user_account`
    - `user_account_aud`

Velo 3.0 tables:

    - `propose`
    - `propose_person_type`
    - `propose_person`
    - `propose_item`
    - `item_type`
    - `property_type`
    - `bussines_type`
    - `plans`
    - `propose_history`
    - `history_type`
    - `document_type`
    - `document_status`
    - `documents`
    - `person_documents`
    - `propose_documents`
    - `delinquency`
    - `deliquency_has_agreement`
    - `agreement`
    - `agreement_payment`

This pipeline produces, in datalake_rental_guarantee_platform_clean:

Via **incremental load**:

    - `address_aud`
    - `company`
    - `company_aud`
    - `company_draft`
    - `company_draft_aud`
    - `company_user_account`
    - `company_user_account_aud`
    - `contract`
    - `contract_aud`
    - `contract_item`
    - `contract_item_aud`
    - `contract_payment`
    - `contract_payment_aud`
    - `contract_payment_hook_history`
    - `contract_payment_hook_history_aud`
    - `contract_person`
    - `contract_person_aud`
    - `contract_status_history`
    - `contract_status_history_aud`
    - `credit_analysis`
    - `credit_analysis_aud`
    - `income_document`
    - `income_document_aud`
    - `person`
    - `person_aud`
    - `profile_account`
    - `profile_account_aud`
    - `property`
    - `property_aud`
    - `rev_info`
    - `user_account`
    - `user_account_aud`

Velo 3.0 tables:

    - `propose`
    - `propose_person_type`
    - `propose_person`
    - `propose_item`
    - `item_type`
    - `property_type`
    - `bussines_type`
    - `plans`
    - `propose_history`
    - `history_type`
    - `document_type`
    - `document_status`
    - `documents`
    - `person_documents`
    - `propose_documents`
    - `delinquency`
    - `deliquency_has_agreement`
    - `agreement`
    - `agreement_payment`

</details>
