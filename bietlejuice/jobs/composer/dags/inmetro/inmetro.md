## Inmetro

### Purpose

This DAG is responsible for the cleansing of the [Inmetro's](https://github.com/quintoandar/inmetro) 
Raw tables. 

Inmetro is a Data Quality python library used in our DAGs where tasks are created based 
on yaml files containing the validations set for each table. More info about this process in [this doc](https://www.notion.so/productquintoandar/Data-Quality-WIP-ead987ee29e44b969b0cff04acab2dc7).

Every Data Quality task created in our DAGs send the results of the validations to inmetro's 
Raw table. This way, this DAG is only responsible for the **Clean** layer process.

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered twice a day.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake clean:

- `data_validations`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
  
</details>