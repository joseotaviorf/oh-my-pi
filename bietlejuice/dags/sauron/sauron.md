## Sauron

### Purpose

Retrieve data from Sauron database (postgresql). [Sauron](https://github.com/quintoandar/sauron) is a internal message orchestration service that manages our sessions.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake:

1. In datalake raw (incremental load):
   - active_sessions
   - bot_outgoing_messages
   - expired_sessions
   - incoming_message_status
   - incoming_messages
   - session
2. In datalake clean (incremental load):
   - active_sessions
   - bot_outgoing_messages
   - expired_sessions
   - incoming_message_status
   - incoming_messages
   - session

### Responsible Data Team

​
For any questions or concerns about this DAG, please contact the Data Engineering team responsible.
