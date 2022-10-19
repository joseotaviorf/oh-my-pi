## DW Sauron
### Purpose
​
This DAG loads the DW tables with the **sessions** data from our Sauron database. [Sauron](https://github.com/quintoandar/sauron) is the messaging orchestration service, and it controls the user session when someone contact our customer service lines.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>​

### Execution Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:
​
- `dim_session`
- `fact_session_tags`
- `fact_sessions`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact its owner.

</details>