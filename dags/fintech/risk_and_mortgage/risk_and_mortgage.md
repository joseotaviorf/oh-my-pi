## Risk and Mortgage

### Purpose
This DAG imports the tables from [Risk And Mortgage](https://github.com/quintoandar/risk-and-mortgage), a service that makes an interface with Itau bank for financing credit approval.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake raw and clean:

Via **incremental load**:
    - `credit_proposal`
    - `offer_pre_analysis`

</details>
