## DW Call
### Purpose
​
This DAG loads the DW tables of our Call data. This data is related to the system named [Bigfone](https://github.com/quintoandar/big-fone), which is responsible for interacting with Twilio (an external service) to manage calls, peers and store data.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>​

### Execution Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:
​
- `dim_call`
- `dim_call_agent`
- `dim_call_task`
- `fact_calls`
- `fact_call_tasks`
- `fact_ivr_paths`

</details>
