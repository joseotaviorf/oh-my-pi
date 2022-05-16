## Enrich Bob

### Purpose

This DAG creates the enriched tables for [Bob (bob-o-construtor)](https://github.com/quintoandar/bob-o-construtor), a house registry service and now it has been used by AA (Autonomous Agents).

### Execution Interval

This DAG is triggered daily via Mediator, after `bob` DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables in the enrich layer, via full load: 
    - `house_draft`
  
And through incremental load:
    - `house_draft_aud`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
  
