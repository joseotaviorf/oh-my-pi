## Casa Mineira Amplitude Portal

### Purpose

This DAG imports the Portal events data of user interaction from Casa Mineira, through Amplitude API.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in **datalake raw and clean**, via incremental load:
    - `events`

### Responsible Data Teams

For any questions or concerns about this DAG and data, please contact the Data Engineering Team or
Data Analytics Team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

### Additional Information

If it is necessary to add a new `app_id` to this DAG, when updating the Secret, you must add it as a JSON array.
</details>