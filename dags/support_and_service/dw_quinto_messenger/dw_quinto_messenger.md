## DW Quinto Messenger
### Purpose
​
This DAG loads the DW tables with **chat** data from our Quinto Messenger database. [Quinto Messenger](https://github.com/quintoandar/quinto-messenger) is the service built to be the connection between Twilio and QuintoAndar's system.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>​

### Execution Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:
​
- `dim_chat`
- `dim_quinto_messenger_agent`
- `dim_task`
- `fact_chats`
- `fact_tasks`

</details>
