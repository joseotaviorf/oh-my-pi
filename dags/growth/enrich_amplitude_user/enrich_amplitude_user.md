## Enrich Amplitude User

### Purpose

Enrich user context events in Amplitude and load into data lake.

This DAG enriches amplitude events that come from user login, user created, and home page visited.
Thus, we can track the user's initial journey in the app.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `user_affiliate_origin`

</details>
