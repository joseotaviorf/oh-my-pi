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
