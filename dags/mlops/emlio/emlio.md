## Emlio

### Purpose

This DAG is responsible for loading machine learning models inputs and associated outputs into our Data Lake. 

Emlio is a logging python library used in machine learning models and services. More info about this process in [this doc](https://www.notion.so/productquintoandar/RFC-ML-model-features-and-predictions-logging-3c6d7680719b4121ad5bb6e1c73d90b1).

Emlio read data from a Kafka topic and write the stream in a hybrid batch/streaming manner. It keep the state of Kafka's offsets, while execute the writing only once.

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once a day.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG produces, via incremental load, the following tables in Raw and Clean layers:

- `emlio_logs`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering or MLOps team that owns it.
  
</details>