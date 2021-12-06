## BigID
### Purpose
Retrieves data from [BigID API](https://github.com/quintoandar/bigid-api-client-python).

BigID is a data governance tool used to catalog product databases and automatically classify if 
their data is PII, sensitive, etc.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Weekly. More information about run time [here]({chart_url}{dag_id}).

### Outputs
We fully load the following tables into the datalake Raw and Clean:

- `data_catalog_entities`

### Responsible Data Team
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
