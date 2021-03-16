## Sorting Hat

### Purpose

Sorting Hat is a microservice responsible for credit policy and analysis for tenants' rental process. This DAG brings its data from a postgreSQL database.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table for both our raw and clean layers:

- `best_subset_5a`
- `best_subset_5aversion`
- `best_subset_cardif_version`
- `best_subset_cardif`
- `best_subset_version`
- `credit_analysis`
- `external_score`
- `best_subset`
- `credit_analysis_version`
- `offer`
- `proponent_version`
- `proponent`
- `proposal_error`
- `proposal_version`
- `proposal`
- `screening_result_version`
- `screening_result`
- `user`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
