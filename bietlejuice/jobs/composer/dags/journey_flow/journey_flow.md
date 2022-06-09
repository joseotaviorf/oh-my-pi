## Journey Flow
### Purpose

Retrieve data from Journey Flow database (postgresql). [Journey Flow](https://github.com/quintoandar/journey-flow)

> Controls journey’s flow. Evaluates which JourneyExecutor (AdaLovelace) version and journeys version must be used, and executes the respective JourneyExecutor and journey version.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake:

1. In datalake raw:

    * t_journey_flow
    * t_dialog
    * t_journey_content
    * t_rule

2. In datalake clean
    
    * journey_flow
    * dialog
    * journey_content
    * rule
    
### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in airflow DAG owners

</details>