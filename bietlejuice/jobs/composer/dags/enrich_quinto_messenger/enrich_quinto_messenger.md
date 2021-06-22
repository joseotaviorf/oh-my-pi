## Enrich Quinto Messenger
### Purpose

Prepares **chat** data from the [Quinto Messenger](github.com/quintoandar/big-fone) for business utilization. [Quinto Messenger](https://github.com/quintoandar/quinto-messenger) is the service built to be the connection between Twilio and QuintoAndar's system.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once per day via Mediator, after `quinto_messenger` DAG, usually around 5:30 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables on enrich layer:

- `task`
- `task_event`
- `channel`
- `channel_event`
- `chat_aht` (AHT stands for Average Handling Time)

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>