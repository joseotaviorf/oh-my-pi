## US Emails

### Purpose

This DAG imports the tables from [US Emails](https://github.com/quintoandar/us-emails), a service responsible for e-mails sent to our customers and detailed information.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake raw and clean:

Via **full load**:
    - `reasons`

Via **incremental load**:
    - `emails`
    - `email_events`
    - `messages`
    - `unsubscriptions`

</details>
