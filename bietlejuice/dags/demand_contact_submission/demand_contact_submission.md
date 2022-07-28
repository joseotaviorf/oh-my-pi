## Demand Contact Submission

### Purpose
This DAG imports the tables from Demand Contact Submission, a platform responsible manage the demand lead contact submission.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake_demand_contact_submission_raw:

Via **incremental load**:
- `contact_submission_types_aud`
- `contact_submission_types`
- `contact_submissions_aud`
- `contact_submissions`
- `message`
- `revinfo`

This pipeline produces, in datalake_demand_contact_submission_clean:

Via **incremental load**:
- `contact_submission_types_aud`
- `contact_submission_types`
- `contact_submissions_aud`
- `contact_submissions`
- `message`
- `rev_info`

</details>