## Big Agent
### Purpose

This DAG imports data from [Big Agent](https://github.com/quintoandar/big-agent), which is an internal microservice responsible for handling the agent and house relationship.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via incremental load:

- In datalake raw:
    - All tables available in database, except for the operationals. 

- In datalake clean:
    - `agency`
    - `agent`
    - `earnings`
    - `enrollment`
    - `house`
    - `program`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
