## Casa Mineira Amplitude

### Purpose

This DAG imports the events data of user interaction from Casa Mineira, through Amplitude API.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in **datalake raw**, via incremental load:
    - `events`

And in **datalake clean**, via incremental load:
    - `329001_portal`

### Additional Information

If it is necessary to add a new `app_id` to this DAG, when updating the Secret, you must add it as a JSON array. Also, we tested to use the Amplitude setup to automatically import data to a S3 bucket but the partitions offered by Amplitude were not suitable and could not be customized.
</details>
