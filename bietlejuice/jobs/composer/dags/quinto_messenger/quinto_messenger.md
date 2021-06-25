## Quinto Messenger
### Purpose

Retrieve data from Quinto Messenger database (postgresql). [Quinto Messenger](https://github.com/quintoandar/quinto-messenger) is the service built to be the connection between Twilio and QuintoAdar's system. 

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>


### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake:
1. In datalake raw:
    * channel
    * channelevent
    * task
    * taskevent
2. In datalake clean
    * channel
    * channel_event
    * task
    * task_event
### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>