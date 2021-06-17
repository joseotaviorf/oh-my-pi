## DW Quinto Messenger
### Purpose
​
This DAG loads the DW tables with **chat** data from our Quinto Messenger database. [Quinto Messenger](https://github.com/quintoandar/quinto-messenger) is the service built to be the connection between Twilio and QuintoAndar's system.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator, after `enrich_quinto_messenger` and `enrich_ebdb_customer_contact_identification` DAGs, usually around 6:00 A.M. UTC.

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

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>