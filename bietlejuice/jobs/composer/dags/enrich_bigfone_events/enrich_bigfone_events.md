## Enrich Bigfone Events
### Purpose

Prepares [Bigfone](github.com/quintoandar/big-fone) data for business utilization. [Bigfone](https://github.com/quintoandar/big-fone) is a system responsible for interacting with Twilio (an external service) to manage calls, peers and store data used to generate some reports. Also, it acts as a central place to identify a person, adding info from Skynet, Akinator, Timeline (from Stalker) and Akinator.

### Execution Interval

This DAG is triggered once per day via Mediator, after `bigfone_events` DAG, usually around 5:00 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer:

- `events`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
