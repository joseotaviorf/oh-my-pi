## Sauron
### Purpose

Retrieve data from Sauron database (postgresql). [Sauron](https://github.com/quintoandar/sauron) is a internal message orchestration service that manages our sessions. 

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake:
1. In datalake raw:
    * active_sessions
    * bot_outgoing_messages
    * expired_sessions
    * incoming_message_status
    * incoming_messages
    * session
2. In datalake clean
    * active_sessions
    * bot_outgoing_messages
    * expired_sessions
    * incoming_message_status
    * incoming_messages
    * session
### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
