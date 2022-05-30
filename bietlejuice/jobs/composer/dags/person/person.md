## Person

### Purpose
This DAG imports the tables from Person, a service that centralizes natural person data.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake_person_raw:

Via **incremental load**:
  - `address`
  - `address_aud`
  - `contact_info`
  - `contact_info_aud`
  - `credential_reference`
  - `credential_reference_aud`
  - `identity_document`
  - `identity_document_aud`
  - `person`
  - `person_aud`
  - `preference_settings`
  - `preference_settings_aud`
  - `rev_info`
  - `right_to_be_forgotten_aud`
  - `right_to_be_forgotten`

This pipeline produces, in datalake_person_clean:

Via **incremental load**:
  - `address`
  - `address_aud`
  - `contact_info`
  - `contact_info_aud`
  - `credential_reference`
  - `credential_reference_aud`
  - `identity_document`
  - `identity_document_aud`
  - `person`
  - `person_aud`
  - `preference_settings`
  - `preference_settings_aud`
  - `rev_info`
  - `right_to_be_forgotten_aud`
  - `right_to_be_forgotten`

### Responsible Data Teams

For any questions or concerns about this DAG and data, please contact the Data For Brokers Team.

</details>
