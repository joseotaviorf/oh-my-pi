## Sorting Hat

### Purpose

Sorting Hat is a microservice responsible for credit policy and analysis for tenants' rental process. This DAG brings its data from a postgreSQL database.

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table for both our raw and clean layers:

- `analysis_machine`
- `analysis_request_data`
- `analysis_request_proponent_data`
- `analysis_request`
- `analysis_state_group`
- `analysis_state`
- `checklist_group`
- `checklist_item`
- `checklist`
- `credit_analysis`
- `credit_analysis_version`
- `early_credit_analysis`
- `experiment`
- `external_score`
- `offer`
- `proponent`
- `proponent_version`
- `proposal`
- `proposal_error`
- `proposal_version`
- `screening_result`
- `screening_result_version`
- `user`
- `variant`

</details>
