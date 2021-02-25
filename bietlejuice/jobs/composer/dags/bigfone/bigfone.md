## Bigfone
### Purpose

Retrieve data from the Bigfone database (PostgreSQL). [Bigfone](https://github.com/quintoandar/big-fone) is a system which is responsible for interacting with Twilio (an external service) to manage calls, peers and store data used to generate some reports. It also acts as a central place to identify a person, adding info from Skynet, Akinator, Timeline (from Stalker) and Akinator.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We perform a full load of the following tables into the datalake Raw and Clean.

- `call`
- `queued`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
