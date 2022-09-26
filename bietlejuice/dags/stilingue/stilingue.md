## Stilingue
### Purpose

Stilingue [client API](https://github.com/quintoandar/stilingue-api-client-python) is a social listening and responding platform. We use the data from this service to serve the public and to generate sentiment analysis and classification.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table for both our raw, staging (clean) and clean layers:

- `report_repliers` (incremental load)
- `calls_report` (incremental load)

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact its owner.

</details>