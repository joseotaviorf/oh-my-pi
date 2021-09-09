## Sorting Hat

### Purpose

Sorting Hat is a microservice responsible for credit policy and analysis for tenants' rental process. This DAG brings its data from a postgreSQL database.

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table for both our raw and clean layers:

- `best_subset`
- `best_subset_5a`
- `best_subset_5aversion`
- `best_subset_cardif`
- `best_subset_cardif_version`
- `best_subset_version`
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

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>