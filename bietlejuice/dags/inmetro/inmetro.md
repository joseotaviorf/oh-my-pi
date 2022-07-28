## Inmetro

### Purpose

This DAG is responsible for loading [Inmetro's](https://github.com/quintoandar/inmetro) 
data into our Data Lake. 

Inmetro is a Data Quality python library used in our DAGs where tasks are created based 
on yaml files containing the validations set for each table. More info about this process in [this doc](https://www.notion.so/productquintoandar/Data-Quality-WIP-ead987ee29e44b969b0cff04acab2dc7).

Every Data Quality task created in our DAGs sends the results of the validations to inmetro's 
bucket in S3. This bucket also contains data from the Wonka dags. We bring all that data incrementally to our data lake.


<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered twice a day.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG produces, via incremental load, the following tables in Raw and Clean layers:

- `data_profiles`
- `data_validations`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team that owns it.
  
</details>