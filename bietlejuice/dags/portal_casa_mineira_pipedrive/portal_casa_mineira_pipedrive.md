## Portal Casa Mineira Pipedrive
### Purpose

The Pipedrive API brings the Portal Casa Mineira deals data and deals flow data. We implement a [client API](https://github.com/quintoandar/pipedrive-api-client-python) for raw use.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Full Load Execution

For execute in full load mode, when you trigger the dag manually, you must send this config JSON with this param:
'execution_date':'2021-01-01'

### Outputs

Currently, there is the following output table for both our raw, staging (clean) and clean layers:

- `deals`
- `deals_flow`
- `stages`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).