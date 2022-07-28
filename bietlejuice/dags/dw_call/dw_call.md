## DW Call
### Purpose
​
This DAG loads the DW tables of our Call data. This data is related to the system named [Bigfone](https://github.com/quintoandar/big-fone), which is responsible for interacting with Twilio (an external service) to manage calls, peers and store data.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>​

### Execution​ Interval
This DAG is triggered once per day via Mediator, after `enrich_bigfone_twilio` DAG, usually around 6:30 A.M. UTC.

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

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>