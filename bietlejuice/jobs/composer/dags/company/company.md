## Company

### Purpose
This DAG imports the tables from Company, a service that centralizes legal entity data.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake_company_raw:

Via **incremental load**:
  - `address`
  - `address_aud`
  - `company`
  - `company_aud`
  - `company_address`
  - `company_address_aud`
  - `company_document`
  - `company_document_aud`
  - `document`
  - `document_aud`
  - `member_profile`
  - `member_profile_aud`
  - `product`
  - `product_aud`
  - `profile`
  - `profile_aud`
  - `profile_hierarchy`
  - `profile_hierarchy_aud`
  - `revinfo`
  - `user_requirements`
  - `user_requirements_aud`

This pipeline produces, in datalake_company_clean:

Via **incremental load**:
  - `address`
  - `address_aud`
  - `company`
  - `company_aud`
  - `company_address`
  - `company_address_aud`
  - `company_document`
  - `company_document_aud`
  - `document`
  - `document_aud`
  - `member_profile`
  - `member_profile_aud`
  - `product`
  - `product_aud`
  - `profile`
  - `profile_aud`
  - `profile_hierarchy`
  - `profile_hierarchy_aud`
  - `rev_info`
  - `user_requirements`
  - `user_requirements_aud`

### Responsible Data Teams

For any questions or concerns about this DAG and data, please contact the Data For Brokers Team.

</details>
