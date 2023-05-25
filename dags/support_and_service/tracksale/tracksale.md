## Tracksale
### Purpose
Retrieves data from [Tracksale API](https://github.com/quintoandar/tracksale-api-client-python). Tracksale is an external service that monitors in real time the customer’s experience. We use it mostly to manage NPS.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
We incrementally load the following tables into the datalake Raw and Clean:

- `dispatch` (generally, do not have data at weekend)
- `answer`
- `campaign`

For further information, please read [this documentation](https://docs.google.com/document/d/15YEa41mdZ2YRUgpKpMNK63sIrHhCSXAYuf2QbW_Df7E).

</details>
